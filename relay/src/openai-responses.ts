import {
  ALLOWED_MODEL,
  MAX_PROVIDER_RESPONSE_BYTES,
  type ModelAnswer,
  type RelaySynthesisRequest,
  validateModelAnswer,
} from "./contracts";
import { modelAnswerSchema } from "./model-schema";

export const RESPONSES_ENDPOINT = "https://api.openai.com/v1/responses";

export type FetchTransport = (request: Request) => Promise<Response>;
export type Sleep = (milliseconds: number) => Promise<void>;

export interface ProviderUsage {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export interface ProviderAnswer {
  answer: ModelAnswer;
  usage: ProviderUsage;
  resolvedModel: string;
  attempts: number;
}

export class ProviderError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly httpStatus: number,
    readonly dispatched: boolean,
    readonly transient: boolean,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}

export class OpenAIResponsesClient {
  constructor(
    private readonly transport: FetchTransport = (request) => fetch(request),
    private readonly sleep: Sleep = (milliseconds) => new Promise((resolve) => {
      setTimeout(resolve, milliseconds);
    }),
  ) {}

  async createAnswer(
    request: RelaySynthesisRequest,
    apiKey: string,
    timeoutMilliseconds: number,
    maximumRetries: number,
    maximumInputTokens: number,
  ): Promise<ProviderAnswer> {
    const body = buildProviderBody(request);
    const encodedBody = new TextEncoder().encode(JSON.stringify(body));
    if (encodedBody.byteLength > maximumInputTokens) {
      throw new ProviderError(
        "input_limit",
        "The complete provider request exceeds the conservative input-token ceiling.",
        413,
        false,
        false,
      );
    }

    let attempts = 0;
    while (attempts <= maximumRetries) {
      attempts += 1;
      try {
        const response = await this.fetchWithTimeout(
          new Request(RESPONSES_ENDPOINT, {
            method: "POST",
            headers: {
              authorization: `Bearer ${apiKey}`,
              "content-type": "application/json",
            },
            body: encodedBody,
          }),
          timeoutMilliseconds,
        );

        if (!response.ok) {
          const transient = response.status === 429 || response.status >= 500;
          if (transient && attempts <= maximumRetries) {
            await this.sleep(250 * attempts);
            continue;
          }
          throw new ProviderError(
            providerCode(response.status),
            `Responses API returned HTTP ${response.status}.`,
            response.status,
            true,
            transient,
          );
        }

        const provider = await parseProviderResponse(response, request);
        return { ...provider, attempts };
      } catch (error) {
        if (error instanceof ProviderError) throw error;
        const timedOut = error instanceof Error && error.name === "AbortError";
        if (attempts <= maximumRetries) {
          await this.sleep(250 * attempts);
          continue;
        }
        throw new ProviderError(
          timedOut ? "timeout" : "transport_failure",
          timedOut ? "Responses API timed out." : "Responses API transport failed.",
          timedOut ? 504 : 502,
          true,
          true,
        );
      }
    }

    throw new ProviderError("retry_exhausted", "Responses API retry limit exhausted.", 502, true, true);
  }

  private async fetchWithTimeout(request: Request, milliseconds: number): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), milliseconds);
    try {
      return await this.transport(new Request(request, { signal: controller.signal }));
    } finally {
      clearTimeout(timeout);
    }
  }
}

export function buildProviderBody(request: RelaySynthesisRequest): Record<string, unknown> {
  const evidence = request.evidencePacket.items.map((item) => ({
    evidenceID: item.id,
    sourceKind: item.sourceKind,
    excerpt: item.excerpt,
    capturedAt: item.capturedAt,
    assertedAt: item.assertedAt,
    coordinate: item.coordinate,
  }));
  const challengeRule = request.purpose === "challenge"
    ? "Evaluate only the independent counterevidence packet against the structured prior judgment. Do not use prior answer prose."
    : "Produce the initial judgment from this packet only. challengeDisposition must be not_run.";

  return {
    model: ALLOWED_MODEL,
    store: false,
    stream: false,
    max_output_tokens: request.maxOutputTokens,
    reasoning: { effort: "low" },
    instructions: [
      "You adjudicate changing everyday facts from bounded evidence.",
      "Never invent evidence or cite an ID outside the supplied packet.",
      "Use unknown when required evidence is absent and ambiguous when supported claims conflict.",
      challengeRule,
    ].join(" "),
    input: JSON.stringify({
      question: request.question,
      purpose: request.purpose,
      structuredPriorJudgment: request.structuredClaim,
      evidence,
    }),
    text: {
      format: {
        type: "json_schema",
        name: "memoed_answer_v1",
        strict: true,
        schema: modelAnswerSchema,
      },
    },
  };
}

async function parseProviderResponse(
  response: Response,
  request: RelaySynthesisRequest,
): Promise<Omit<ProviderAnswer, "attempts">> {
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("text/event-stream")) {
    throw new ProviderError(
      "unexpected_stream",
      "The non-streaming relay received an event stream.",
      502,
      true,
      false,
    );
  }

  const bytes = await readBoundedBody(response, MAX_PROVIDER_RESPONSE_BYTES);
  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new ProviderError("truncated_response", "Provider response was not complete JSON.", 502, true, false);
  }

  const root = asRecord(payload, "provider response");
  if (root.status !== "completed") {
    throw new ProviderError(
      root.status === "incomplete" ? "incomplete_response" : "provider_not_completed",
      "Provider response did not complete.",
      502,
      true,
      false,
    );
  }

  const output = Array.isArray(root.output) ? root.output : [];
  const contents = output.flatMap((item) => {
    const message = asRecord(item, "provider output");
    return Array.isArray(message.content) ? message.content : [];
  });
  for (const content of contents) {
    const item = asRecord(content, "provider content");
    if (item.type === "refusal") {
      throw new ProviderError("refusal", "The model refused this request.", 422, true, false);
    }
  }
  const outputText = contents
    .map((content) => asRecord(content, "provider content"))
    .find((content) => content.type === "output_text");
  if (typeof outputText?.text !== "string") {
    throw new ProviderError("missing_output", "Provider response had no output_text content.", 502, true, false);
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(outputText.text);
  } catch {
    throw new ProviderError("invalid_schema", "Structured output was not JSON.", 502, true, false);
  }

  let answer: ModelAnswer;
  try {
    answer = validateModelAnswer(decoded, request);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Structured output failed validation.";
    throw new ProviderError("invalid_schema", message, 502, true, false);
  }

  const usage = asRecord(root.usage, "provider usage");
  const inputTokens = nonnegativeInteger(usage.input_tokens, "usage.input_tokens");
  const outputTokens = nonnegativeInteger(usage.output_tokens, "usage.output_tokens");
  const totalTokens = nonnegativeInteger(usage.total_tokens, "usage.total_tokens");
  if (inputTokens > 12_000 || outputTokens > request.maxOutputTokens || totalTokens < inputTokens + outputTokens) {
    throw new ProviderError("usage_limit", "Provider usage exceeded the relay contract.", 502, true, false);
  }
  const resolvedModel = typeof root.model === "string" ? root.model : "";
  if (resolvedModel !== ALLOWED_MODEL && !resolvedModel.startsWith(`${ALLOWED_MODEL}-`)) {
    throw new ProviderError("model_mismatch", "Provider resolved an unexpected model.", 502, true, false);
  }

  return {
    answer,
    usage: { inputTokens, outputTokens, totalTokens },
    resolvedModel,
  };
}

async function readBoundedBody(response: Response, maximumBytes: number): Promise<Uint8Array> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new ProviderError("response_limit", "Provider response exceeded the byte limit.", 502, true, false);
  }
  if (response.body === null) {
    throw new ProviderError("empty_response", "Provider response body was empty.", 502, true, false);
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maximumBytes) {
      await reader.cancel();
      throw new ProviderError("response_limit", "Provider response exceeded the byte limit.", 502, true, false);
    }
    chunks.push(value);
  }

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function asRecord(value: unknown, path: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new ProviderError("invalid_provider_response", `${path} must be an object.`, 502, true, false);
  }
  return value as Record<string, unknown>;
}

function nonnegativeInteger(value: unknown, path: string): number {
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw new ProviderError("invalid_provider_response", `${path} must be nonnegative.`, 502, true, false);
  }
  return value as number;
}

function providerCode(status: number): string {
  if (status === 400) return "provider_schema_rejected";
  if (status === 401 || status === 403) return "provider_unauthorized";
  if (status === 429) return "provider_rate_limited";
  if (status >= 500) return "provider_unavailable";
  return "provider_error";
}

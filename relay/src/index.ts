import {
  ALLOWED_MODEL,
  ContractError,
  MAX_REQUEST_BYTES,
  RESPONSE_SCHEMA_VERSION,
  type RelaySynthesisResponse,
  validateRelayRequest,
} from "./contracts";
import {
  OpenAIResponsesClient,
  ProviderError,
} from "./openai-responses";
import { BudgetLedger, type ProviderOutcome } from "./budget-ledger";

export { BudgetLedger };

export default {
  async fetch(request: Request, env: Cloudflare.Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({
        status: "ok",
        liveAPIEnabled: isLiveAPIEnabled(env.OPENAI_LIVE_API_ENABLED),
        model: ALLOWED_MODEL,
      });
    }
    if (request.method === "DELETE" && url.pathname === "/v1/installations/current") {
      return deleteInstallation(request, env);
    }
    if (request.method !== "POST" || url.pathname !== "/v1/synthesize") {
      return errorResponse(404, "not_found");
    }
    return synthesize(request, env);
  },
} satisfies ExportedHandler<Cloudflare.Env>;

async function synthesize(request: Request, env: Cloudflare.Env): Promise<Response> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return errorResponse(415, "unsupported_media_type");
  }

  let payload: unknown;
  try {
    const bytes = await readBoundedRequest(request, MAX_REQUEST_BYTES);
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof ContractError) return errorResponse(413, error.code);
    return errorResponse(400, "invalid_json");
  }

  let synthesisRequest;
  try {
    synthesisRequest = validateRelayRequest(payload);
  } catch (error) {
    if (error instanceof ContractError) return errorResponse(400, error.code);
    return errorResponse(400, "invalid_request");
  }

  const dailyBudget = positiveInteger(env.OPENAI_DAILY_BUDGET_MICRO_USD);
  const flowBudget = positiveInteger(env.OPENAI_FLOW_BUDGET_MICRO_USD);
  if (!isLiveAPIEnabled(env.OPENAI_LIVE_API_ENABLED) || dailyBudget === 0 || flowBudget === 0) {
    return errorResponse(503, "live_api_disabled");
  }

  const installation = request.headers.get("x-memoed-installation") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(installation)) {
    return errorResponse(401, "installation_required");
  }

  const maximumInputTokens = boundedEnvironmentInteger(env.OPENAI_MAX_INPUT_TOKENS, 12_000, 1, 12_000);
  const maximumOutputTokens = boundedEnvironmentInteger(env.OPENAI_MAX_OUTPUT_TOKENS, 2_000, 1, 2_000);
  if (synthesisRequest.maxOutputTokens > maximumOutputTokens) {
    return errorResponse(400, "output_limit");
  }
  const timeout = boundedEnvironmentInteger(env.OPENAI_TIMEOUT_MS, 20_000, 1_000, 20_000);
  const retries = boundedEnvironmentInteger(env.OPENAI_MAX_RETRIES, 1, 0, 1);
  const worstCaseMicroUSD = estimatedMicroUSD(maximumInputTokens, synthesisRequest.maxOutputTokens);
  const now = Date.now();
  const reservationID = crypto.randomUUID();
  const installationHash = await sha256(installation);
  const dateKey = new Date(now).toISOString().slice(0, 10);
  const ledger = env.BUDGET_LEDGER.getByName("global:v1");
  const reservation = await ledger.reserve({
    reservationID,
    dateKey,
    flowID: synthesisRequest.flowID,
    installationHash,
    worstCaseMicroUSD,
    dailyBudgetMicroUSD: dailyBudget,
    flowBudgetMicroUSD: flowBudget,
    maxCallsPerFlow: 4,
    maxCallsPerMinute: 4,
    nowUnixMilliseconds: now,
  });
  if (!reservation.accepted) {
    const status = reservation.code === "rate_limit" ? 429 : 503;
    return errorResponse(status, reservation.code);
  }

  const apiKey = env.OPENAI_API_KEY?.trim() ?? "";
  if (!apiKey) {
    await ledger.release(reservationID);
    return errorResponse(503, "provider_not_configured");
  }

  const client = new OpenAIResponsesClient();
  try {
    const provider = await client.createAnswer(
      synthesisRequest,
      apiKey,
      timeout,
      retries,
      maximumInputTokens,
    );
    const actualMicroUSD = estimatedMicroUSD(
      provider.usage.inputTokens,
      provider.usage.outputTokens,
    );
    await ledger.settle(reservationID, actualMicroUSD, "success", Date.now());
    const response: RelaySynthesisResponse = {
      schemaVersion: RESPONSE_SCHEMA_VERSION,
      source: "cloud",
      model: ALLOWED_MODEL,
      ...provider.answer,
    };
    return json(response);
  } catch (error) {
    if (error instanceof ProviderError) {
      if (error.dispatched) {
        const outcome: ProviderOutcome = error.transient
          ? "transientFailure"
          : error.code === "provider_unauthorized"
            ? "permanentFailure"
            : "neutralFailure";
        await ledger.settle(reservationID, worstCaseMicroUSD, outcome, Date.now());
      } else {
        await ledger.release(reservationID);
      }
      return errorResponse(error.httpStatus, error.code);
    }
    await ledger.settle(reservationID, worstCaseMicroUSD, "transientFailure", Date.now());
    return errorResponse(502, "relay_failure");
  }
}

async function deleteInstallation(request: Request, env: Cloudflare.Env): Promise<Response> {
  const installation = request.headers.get("x-memoed-installation") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(installation)) {
    return errorResponse(401, "installation_required");
  }
  const installationHash = await sha256(installation);
  const ledger = env.BUDGET_LEDGER.getByName("global:v1");
  await ledger.purgeInstallation(installationHash);
  return new Response(null, {
    status: 204,
    headers: {
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}

async function readBoundedRequest(request: Request, maximumBytes: number): Promise<Uint8Array> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new ContractError("request_limit", "Request body is too large.");
  }
  if (request.body === null) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maximumBytes) {
      await reader.cancel();
      throw new ContractError("request_limit", "Request body is too large.");
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

function json(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
      "x-content-type-options": "nosniff",
    },
  });
}

function errorResponse(status: number, code: string): Response {
  return json({ error: { code } }, status);
}

function positiveInteger(value: string): number {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 0;
}

function isLiveAPIEnabled(value: string): boolean {
  return value === "true";
}

function boundedEnvironmentInteger(
  value: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : fallback;
}

function estimatedMicroUSD(inputTokens: number, outputTokens: number): number {
  return Math.ceil(inputTokens * 0.75 + outputTokens * 4.5);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

import { describe, expect, it } from "vitest";
import {
  OpenAIResponsesClient,
  buildProviderBody,
  type FetchTransport,
} from "../src/openai-responses";
import { modelAnswer, providerResponse, relayRequest } from "./fixtures";

describe("Responses API fixture transport", () => {
  it("sends the pinned model, store=false, hard output cap, and strict schema", async () => {
    let captured: Record<string, unknown> | undefined;
    const transport: FetchTransport = async (request) => {
      captured = JSON.parse(await request.text()) as Record<string, unknown>;
      return providerResponse();
    };
    const result = await client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 1, 12_000);
    const text = captured?.text as { format?: { strict?: boolean } } | undefined;
    expect(captured?.model).toBe("gpt-5.4-mini");
    expect(captured?.store).toBe(false);
    expect(captured?.max_output_tokens).toBe(2_000);
    expect(text?.format?.strict).toBe(true);
    expect(result.answer.verdict).toBe("current");
    expect(result.attempts).toBe(1);
  });

  it("does not retry a provider schema 400", async () => {
    let calls = 0;
    const transport: FetchTransport = async () => {
      calls += 1;
      return new Response("{}", { status: 400 });
    };
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 1, 12_000))
      .rejects.toMatchObject({ code: "provider_schema_rejected", httpStatus: 400 });
    expect(calls).toBe(1);
  });

  it("does not retry an unauthorized 401", async () => {
    let calls = 0;
    const transport: FetchTransport = async () => {
      calls += 1;
      return new Response("{}", { status: 401 });
    };
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 1, 12_000))
      .rejects.toMatchObject({ code: "provider_unauthorized", httpStatus: 401 });
    expect(calls).toBe(1);
  });

  it("retries one 429 and then accepts a valid response", async () => {
    let calls = 0;
    const transport: FetchTransport = async () => {
      calls += 1;
      return calls === 1 ? new Response("{}", { status: 429 }) : providerResponse();
    };
    const result = await client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 1, 12_000);
    expect(result.attempts).toBe(2);
    expect(calls).toBe(2);
  });

  it("stops after one retry when 500 persists", async () => {
    let calls = 0;
    const transport: FetchTransport = async () => {
      calls += 1;
      return new Response("{}", { status: 500 });
    };
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 1, 12_000))
      .rejects.toMatchObject({ code: "provider_unavailable", httpStatus: 500 });
    expect(calls).toBe(2);
  });

  it("turns a timed-out fixture into a bounded timeout error", async () => {
    const transport: FetchTransport = (request) => new Promise((_resolve, reject) => {
      request.signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
    });
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 1, 0, 12_000))
      .rejects.toMatchObject({ code: "timeout", httpStatus: 504 });
  });

  it("rejects truncated JSON and unexpected event streams", async () => {
    const truncated: FetchTransport = async () => new Response("{\"status\":", {
      headers: { "content-type": "application/json" },
    });
    await expect(client(truncated).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "truncated_response" });

    const stream: FetchTransport = async () => new Response("event: response.completed", {
      headers: { "content-type": "text/event-stream" },
    });
    await expect(client(stream).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "unexpected_stream" });
  });

  it("rejects provider-valid JSON that violates evidence integrity", async () => {
    const invalid = modelAnswer();
    invalid.claims[0]?.evidenceIDs.push("outside-packet");
    const transport: FetchTransport = async () => providerResponse(invalid);
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "invalid_schema" });
  });

  it("rejects a provider response resolved by any model outside the allowlist", async () => {
    const transport: FetchTransport = async () => providerResponse(modelAnswer(), "gpt-5.6");
    await expect(client(transport).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "model_mismatch" });
  });

  it("fails closed on incomplete responses and refusals", async () => {
    const incomplete: FetchTransport = async () => Response.json({
      status: "incomplete",
      model: "gpt-5.4-mini-2026-03-17",
      output: [],
      usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 },
    });
    await expect(client(incomplete).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "incomplete_response" });

    const refusal: FetchTransport = async () => Response.json({
      status: "completed",
      model: "gpt-5.4-mini-2026-03-17",
      output: [{ content: [{ type: "refusal", refusal: "Cannot comply." }] }],
      usage: { input_tokens: 10, output_tokens: 4, total_tokens: 14 },
    });
    await expect(client(refusal).createAnswer(relayRequest(), "fixture-key", 20_000, 0, 12_000))
      .rejects.toMatchObject({ code: "refusal" });
  });

  it("keeps the conservative complete-request byte ceiling below the token cap", () => {
    const bytes = new TextEncoder().encode(JSON.stringify(buildProviderBody(relayRequest())));
    expect(bytes.byteLength).toBeLessThanOrEqual(12_000);
  });
});

function client(transport: FetchTransport): OpenAIResponsesClient {
  return new OpenAIResponsesClient(transport, async () => undefined);
}

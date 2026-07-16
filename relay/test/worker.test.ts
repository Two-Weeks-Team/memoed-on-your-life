import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { relayRequest } from "./fixtures";

describe("Worker fail-closed routes", () => {
  it("reports the allowed model without exposing configuration secrets", async () => {
    const response = await exports.default.fetch("https://relay.test/health");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      liveAPIEnabled: false,
      model: "gpt-5.4-mini",
    });
  });

  it("blocks upstream before reading a key while the USD budget is zero", async () => {
    expect(env.OPENAI_DAILY_BUDGET_MICRO_USD).toBe("0");
    const response = await exports.default.fetch(
      new Request("https://relay.test/v1/synthesize", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-memoed-installation": "fixture_installation_001",
        },
        body: JSON.stringify(relayRequest()),
      }),
    );
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: { code: "live_api_disabled" } });
  });
});

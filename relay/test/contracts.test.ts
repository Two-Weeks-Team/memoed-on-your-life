import { describe, expect, it } from "vitest";
import {
  ContractError,
  validateModelAnswer,
  validateRelayRequest,
} from "../src/contracts";
import { modelAnswer, relayRequest } from "./fixtures";

describe("relay contracts", () => {
  it("accepts the bounded gpt-5.4-mini request", () => {
    expect(validateRelayRequest(relayRequest())).toEqual(relayRequest());
  });

  it("rejects every model outside the single allowlist", () => {
    const request = { ...relayRequest(), model: "gpt-5.6" };
    expect(() => validateRelayRequest(request)).toThrowError(ContractError);
  });

  it("rejects extra fields instead of silently ignoring them", () => {
    const request = { ...relayRequest(), apiKey: "must-never-be-sent" };
    expect(() => validateRelayRequest(request)).toThrow(/missing or unexpected/i);
  });

  it("rejects citations outside the independently allowed packet", () => {
    const answer = modelAnswer();
    answer.claims[0]?.evidenceIDs.push("invented-evidence");
    expect(() => validateModelAnswer(answer, relayRequest())).toThrow(/outside its packet/i);
  });

  it("permits an honest unknown claim without fabricated evidence", () => {
    const answer = modelAnswer();
    answer.verdict = "unknown";
    answer.claims[0] = {
      id: "dinner-time",
      text: "The current time is unknown.",
      status: "unknown",
      confidence: "low",
      evidenceIDs: [],
    };
    answer.missingEvidence = ["A current correction is missing."];
    expect(validateModelAnswer(answer, relayRequest()).verdict).toBe("unknown");
  });
});

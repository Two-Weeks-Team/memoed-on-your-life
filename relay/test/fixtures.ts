import {
  ALLOWED_MODEL,
  REQUEST_SCHEMA_VERSION,
  type ModelAnswer,
  type RelaySynthesisRequest,
} from "../src/contracts";

export function relayRequest(): RelaySynthesisRequest {
  return {
    schemaVersion: REQUEST_SCHEMA_VERSION,
    flowID: "flow_fixture_001",
    model: ALLOWED_MODEL,
    purpose: "default",
    question: "When is dinner now?",
    maxOutputTokens: 2_000,
    structuredClaim: null,
    evidencePacket: {
      purpose: "default",
      items: [
        {
          id: "photo-correction",
          sourceKind: "image_ocr_crop",
          excerpt: "Corrected invitation: Friday at 6:30 PM.",
          capturedAt: "2026-07-16T00:00:00.000Z",
          assertedAt: "2026-07-15T10:00:00.000Z",
          coordinate: {
            kind: "normalized_crop",
            startMilliseconds: null,
            endMilliseconds: null,
            x: 0.08,
            y: 0.18,
            width: 0.84,
            height: 0.22,
          },
        },
      ],
    },
  };
}

export function modelAnswer(): ModelAnswer {
  return {
    verdict: "current",
    answer: "Dinner is Friday at 6:30 PM.",
    claims: [
      {
        id: "dinner-time",
        text: "Dinner is Friday at 6:30 PM.",
        status: "current",
        confidence: "high",
        evidenceIDs: ["photo-correction"],
      },
    ],
    why: "The invitation explicitly corrects the earlier plan.",
    missingEvidence: [],
    challengeDisposition: "not_run",
  };
}

export function providerResponse(
  answer: ModelAnswer = modelAnswer(),
  resolvedModel = "gpt-5.4-mini-2026-03-17",
): Response {
  return Response.json({
    id: "resp_fixture",
    object: "response",
    status: "completed",
    model: resolvedModel,
    output: [
      {
        type: "message",
        role: "assistant",
        content: [{ type: "output_text", text: JSON.stringify(answer) }],
      },
    ],
    usage: {
      input_tokens: 900,
      output_tokens: 180,
      total_tokens: 1_080,
    },
  });
}

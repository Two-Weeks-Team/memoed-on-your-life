export const modelAnswerSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "verdict",
    "answer",
    "claims",
    "why",
    "missingEvidence",
    "challengeDisposition",
  ],
  properties: {
    verdict: {
      type: "string",
      enum: ["current", "superseded", "ambiguous", "unknown"],
    },
    answer: { type: "string" },
    claims: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["id", "text", "status", "confidence", "evidenceIDs"],
        properties: {
          id: { type: "string" },
          text: { type: "string" },
          status: {
            type: "string",
            enum: ["current", "superseded", "ambiguous", "unknown"],
          },
          confidence: {
            type: "string",
            enum: ["low", "medium", "high"],
          },
          evidenceIDs: {
            type: "array",
            items: { type: "string" },
          },
        },
      },
    },
    why: { type: "string" },
    missingEvidence: {
      type: "array",
      items: { type: "string" },
    },
    challengeDisposition: {
      type: "string",
      enum: ["not_run", "upheld", "narrowed", "revised", "ambiguous"],
    },
  },
} as const;

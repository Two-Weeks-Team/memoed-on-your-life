export const ALLOWED_MODEL = "gpt-5.4-mini" as const;
export const REQUEST_SCHEMA_VERSION = "memoed.relay.request.v1" as const;
export const RESPONSE_SCHEMA_VERSION = "memoed.relay.response.v1" as const;
export const MAX_REQUEST_BYTES = 64 * 1024;
export const MAX_PROVIDER_RESPONSE_BYTES = 128 * 1024;
export const MAX_EVIDENCE_BYTES = 6_000;
export const MAX_EVIDENCE_ITEMS = 12;
export const MAX_OUTPUT_TOKENS = 2_000;

export type SynthesisPurpose = "default" | "challenge";
export type Verdict = "current" | "superseded" | "ambiguous" | "unknown";
export type ConfidenceBand = "low" | "medium" | "high";
export type ChallengeDisposition =
  | "not_run"
  | "upheld"
  | "narrowed"
  | "revised"
  | "ambiguous";

export interface RelayCoordinate {
  kind: "audio_interval" | "normalized_crop";
  startMilliseconds: number | null;
  endMilliseconds: number | null;
  x: number | null;
  y: number | null;
  width: number | null;
  height: number | null;
}

export interface RelayEvidenceItem {
  id: string;
  sourceKind: "audio_transcript_span" | "image_ocr_crop";
  excerpt: string;
  capturedAt: string;
  assertedAt: string | null;
  coordinate: RelayCoordinate;
}

export interface StructuredClaim {
  id: string;
  text: string;
  status: Verdict;
  evidenceIDs: string[];
}

export interface PriorJudgment {
  verdict: Verdict;
  claims: StructuredClaim[];
}

export interface RelaySynthesisRequest {
  schemaVersion: typeof REQUEST_SCHEMA_VERSION;
  flowID: string;
  model: typeof ALLOWED_MODEL;
  purpose: SynthesisPurpose;
  question: string;
  maxOutputTokens: number;
  structuredClaim: PriorJudgment | null;
  evidencePacket: {
    purpose: SynthesisPurpose;
    items: RelayEvidenceItem[];
  };
}

export interface ModelClaim {
  id: string;
  text: string;
  status: Verdict;
  confidence: ConfidenceBand;
  evidenceIDs: string[];
}

export interface ModelAnswer {
  verdict: Verdict;
  answer: string;
  claims: ModelClaim[];
  why: string;
  missingEvidence: string[];
  challengeDisposition: ChallengeDisposition;
}

export interface RelaySynthesisResponse extends ModelAnswer {
  schemaVersion: typeof RESPONSE_SCHEMA_VERSION;
  source: "cloud";
  model: typeof ALLOWED_MODEL;
}

export class ContractError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ContractError";
  }
}

export function validateRelayRequest(value: unknown): RelaySynthesisRequest {
  const root = record(value, "request");
  exactKeys(root, [
    "schemaVersion",
    "flowID",
    "model",
    "purpose",
    "question",
    "maxOutputTokens",
    "structuredClaim",
    "evidencePacket",
  ], "request");

  literal(root.schemaVersion, REQUEST_SCHEMA_VERSION, "schemaVersion");
  literal(root.model, ALLOWED_MODEL, "model");
  const purpose = synthesisPurpose(root.purpose, "purpose");
  const flowID = boundedID(root.flowID, "flowID");
  const question = boundedString(root.question, "question", 1, 1_000);
  const maxOutputTokens = boundedInteger(
    root.maxOutputTokens,
    "maxOutputTokens",
    1,
    MAX_OUTPUT_TOKENS,
  );
  const structuredClaim = root.structuredClaim === null
    ? null
    : validatePriorJudgment(root.structuredClaim);
  if (purpose === "default" && structuredClaim !== null) {
    fail("invalid_request", "Default synthesis must not receive a prior judgment.");
  }
  if (purpose === "challenge" && structuredClaim === null) {
    fail("invalid_request", "Challenge synthesis requires a structured prior judgment.");
  }

  const packet = record(root.evidencePacket, "evidencePacket");
  exactKeys(packet, ["purpose", "items"], "evidencePacket");
  const packetPurpose = synthesisPurpose(packet.purpose, "evidencePacket.purpose");
  if (packetPurpose !== purpose) {
    fail("invalid_request", "Evidence packet purpose must match request purpose.");
  }
  const rawItems = array(packet.items, "evidencePacket.items", 1, MAX_EVIDENCE_ITEMS);
  const items = rawItems.map((item, index) => validateEvidenceItem(item, index));
  unique(items.map((item) => item.id), "evidencePacket.items[].id");

  const evidenceBytes = items.reduce(
    (total, item) => total + new TextEncoder().encode(item.excerpt).byteLength,
    0,
  );
  if (evidenceBytes > MAX_EVIDENCE_BYTES) {
    fail("input_limit", `Evidence excerpts exceed ${MAX_EVIDENCE_BYTES} UTF-8 bytes.`);
  }

  return {
    schemaVersion: REQUEST_SCHEMA_VERSION,
    flowID,
    model: ALLOWED_MODEL,
    purpose,
    question,
    maxOutputTokens,
    structuredClaim,
    evidencePacket: { purpose: packetPurpose, items },
  };
}

export function validateModelAnswer(
  value: unknown,
  request: RelaySynthesisRequest,
): ModelAnswer {
  const root = record(value, "model answer");
  exactKeys(root, [
    "verdict",
    "answer",
    "claims",
    "why",
    "missingEvidence",
    "challengeDisposition",
  ], "model answer");

  const verdict = verdictValue(root.verdict, "verdict");
  const answer = boundedString(root.answer, "answer", 1, 1_000);
  const why = boundedString(root.why, "why", 1, 2_000);
  const claims = array(root.claims, "claims", 0, 12)
    .map((claim, index) => validateModelClaim(claim, index));
  unique(claims.map((claim) => claim.id), "claims[].id");
  const missingEvidence = array(root.missingEvidence, "missingEvidence", 0, 8)
    .map((item, index) => boundedString(item, `missingEvidence[${index}]`, 1, 300));
  unique(missingEvidence, "missingEvidence");

  const disposition = challengeDisposition(root.challengeDisposition);
  if (request.purpose === "default" && disposition !== "not_run") {
    fail("invalid_schema", "Default synthesis must use challengeDisposition=not_run.");
  }
  if (request.purpose === "challenge" && disposition === "not_run") {
    fail("invalid_schema", "Challenge synthesis must return a challenge disposition.");
  }

  const allowed = new Set(request.evidencePacket.items.map((item) => item.id));
  for (const claim of claims) {
    if (claim.status !== "unknown" && claim.evidenceIDs.length === 0) {
      fail("evidence_integrity", `Claim ${claim.id} has no evidence ID.`);
    }
    if (claim.evidenceIDs.some((id) => !allowed.has(id))) {
      fail("evidence_integrity", `Claim ${claim.id} cites evidence outside its packet.`);
    }
  }

  return {
    verdict,
    answer,
    claims,
    why,
    missingEvidence,
    challengeDisposition: disposition,
  };
}

function validateEvidenceItem(value: unknown, index: number): RelayEvidenceItem {
  const path = `evidencePacket.items[${index}]`;
  const item = record(value, path);
  exactKeys(item, [
    "id",
    "sourceKind",
    "excerpt",
    "capturedAt",
    "assertedAt",
    "coordinate",
  ], path);
  const sourceKind = oneOf(
    item.sourceKind,
    ["audio_transcript_span", "image_ocr_crop"] as const,
    `${path}.sourceKind`,
  );
  const coordinate = validateCoordinate(item.coordinate, sourceKind, `${path}.coordinate`);
  return {
    id: boundedID(item.id, `${path}.id`),
    sourceKind,
    excerpt: boundedString(item.excerpt, `${path}.excerpt`, 1, 2_000),
    capturedAt: isoDate(item.capturedAt, `${path}.capturedAt`),
    assertedAt: item.assertedAt === null
      ? null
      : isoDate(item.assertedAt, `${path}.assertedAt`),
    coordinate,
  };
}

function validateCoordinate(
  value: unknown,
  sourceKind: RelayEvidenceItem["sourceKind"],
  path: string,
): RelayCoordinate {
  const coordinate = record(value, path);
  exactKeys(coordinate, [
    "kind",
    "startMilliseconds",
    "endMilliseconds",
    "x",
    "y",
    "width",
    "height",
  ], path);
  const kind = oneOf(
    coordinate.kind,
    ["audio_interval", "normalized_crop"] as const,
    `${path}.kind`,
  );

  if (sourceKind === "audio_transcript_span" && kind !== "audio_interval") {
    fail("invalid_request", `${path} does not match its audio source kind.`);
  }
  if (sourceKind === "image_ocr_crop" && kind !== "normalized_crop") {
    fail("invalid_request", `${path} does not match its image source kind.`);
  }

  if (kind === "audio_interval") {
    const start = boundedInteger(coordinate.startMilliseconds, `${path}.startMilliseconds`, 0, 86_400_000);
    const end = boundedInteger(coordinate.endMilliseconds, `${path}.endMilliseconds`, 1, 86_400_000);
    if (end <= start) fail("invalid_request", `${path} audio interval is empty.`);
    allNull(coordinate, ["x", "y", "width", "height"], path);
    return {
      kind,
      startMilliseconds: start,
      endMilliseconds: end,
      x: null,
      y: null,
      width: null,
      height: null,
    };
  }

  allNull(coordinate, ["startMilliseconds", "endMilliseconds"], path);
  const x = boundedNumber(coordinate.x, `${path}.x`, 0, 1);
  const y = boundedNumber(coordinate.y, `${path}.y`, 0, 1);
  const width = boundedNumber(coordinate.width, `${path}.width`, 0.000_001, 1);
  const height = boundedNumber(coordinate.height, `${path}.height`, 0.000_001, 1);
  if (x + width > 1.000_001 || y + height > 1.000_001) {
    fail("invalid_request", `${path} crop exceeds normalized bounds.`);
  }
  return {
    kind,
    startMilliseconds: null,
    endMilliseconds: null,
    x,
    y,
    width,
    height,
  };
}

function validatePriorJudgment(value: unknown): PriorJudgment {
  const judgment = record(value, "structuredClaim");
  exactKeys(judgment, ["verdict", "claims"], "structuredClaim");
  const claims = array(judgment.claims, "structuredClaim.claims", 1, 12)
    .map((claim, index) => validateStructuredClaim(claim, index));
  unique(claims.map((claim) => claim.id), "structuredClaim.claims[].id");
  return {
    verdict: verdictValue(judgment.verdict, "structuredClaim.verdict"),
    claims,
  };
}

function validateStructuredClaim(value: unknown, index: number): StructuredClaim {
  const path = `structuredClaim.claims[${index}]`;
  const claim = record(value, path);
  exactKeys(claim, ["id", "text", "status", "evidenceIDs"], path);
  return {
    id: boundedID(claim.id, `${path}.id`),
    text: boundedString(claim.text, `${path}.text`, 1, 1_000),
    status: verdictValue(claim.status, `${path}.status`),
    evidenceIDs: uniqueStrings(claim.evidenceIDs, `${path}.evidenceIDs`, 0, 12),
  };
}

function validateModelClaim(value: unknown, index: number): ModelClaim {
  const path = `claims[${index}]`;
  const claim = record(value, path);
  exactKeys(claim, ["id", "text", "status", "confidence", "evidenceIDs"], path);
  return {
    id: boundedID(claim.id, `${path}.id`),
    text: boundedString(claim.text, `${path}.text`, 1, 1_000),
    status: verdictValue(claim.status, `${path}.status`),
    confidence: oneOf(
      claim.confidence,
      ["low", "medium", "high"] as const,
      `${path}.confidence`,
    ),
    evidenceIDs: uniqueStrings(claim.evidenceIDs, `${path}.evidenceIDs`, 0, 12),
  };
}

function challengeDisposition(value: unknown): ChallengeDisposition {
  return oneOf(
    value,
    ["not_run", "upheld", "narrowed", "revised", "ambiguous"] as const,
    "challengeDisposition",
  );
}

function verdictValue(value: unknown, path: string): Verdict {
  return oneOf(value, ["current", "superseded", "ambiguous", "unknown"] as const, path);
}

function synthesisPurpose(value: unknown, path: string): SynthesisPurpose {
  return oneOf(value, ["default", "challenge"] as const, path);
}

function record(value: unknown, path: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail("invalid_schema", `${path} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, expected: string[], path: string): void {
  const actual = Object.keys(value).sort();
  const required = [...expected].sort();
  if (actual.length !== required.length || actual.some((key, index) => key !== required[index])) {
    fail("invalid_schema", `${path} has missing or unexpected fields.`);
  }
}

function array(value: unknown, path: string, minimum: number, maximum: number): unknown[] {
  if (!Array.isArray(value) || value.length < minimum || value.length > maximum) {
    fail("invalid_schema", `${path} must contain ${minimum}...${maximum} items.`);
  }
  return value;
}

function boundedString(
  value: unknown,
  path: string,
  minimum: number,
  maximum: number,
): string {
  if (typeof value !== "string" || value.length < minimum || value.length > maximum) {
    fail("invalid_schema", `${path} must contain ${minimum}...${maximum} characters.`);
  }
  return value;
}

function boundedID(value: unknown, path: string): string {
  const result = boundedString(value, path, 1, 128);
  if (!/^[A-Za-z0-9][A-Za-z0-9:_-]*$/.test(result)) {
    fail("invalid_schema", `${path} contains unsupported characters.`);
  }
  return result;
}

function boundedInteger(
  value: unknown,
  path: string,
  minimum: number,
  maximum: number,
): number {
  if (!Number.isInteger(value) || (value as number) < minimum || (value as number) > maximum) {
    fail("invalid_schema", `${path} must be an integer in ${minimum}...${maximum}.`);
  }
  return value as number;
}

function boundedNumber(
  value: unknown,
  path: string,
  minimum: number,
  maximum: number,
): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    fail("invalid_schema", `${path} must be a number in ${minimum}...${maximum}.`);
  }
  return value;
}

function isoDate(value: unknown, path: string): string {
  const result = boundedString(value, path, 20, 40);
  if (!Number.isFinite(Date.parse(result))) {
    fail("invalid_schema", `${path} must be an ISO-8601 timestamp.`);
  }
  return result;
}

function literal<T extends string>(value: unknown, expected: T, path: string): T {
  if (value !== expected) fail("invalid_schema", `${path} must equal ${expected}.`);
  return expected;
}

function oneOf<const T extends readonly string[]>(
  value: unknown,
  allowed: T,
  path: string,
): T[number] {
  if (typeof value !== "string" || !allowed.includes(value)) {
    fail("invalid_schema", `${path} is not an allowed value.`);
  }
  return value as T[number];
}

function allNull(value: Record<string, unknown>, keys: string[], path: string): void {
  if (keys.some((key) => value[key] !== null)) {
    fail("invalid_schema", `${path} contains coordinates for the wrong source kind.`);
  }
}

function uniqueStrings(
  value: unknown,
  path: string,
  minimum: number,
  maximum: number,
): string[] {
  const result = array(value, path, minimum, maximum)
    .map((item, index) => boundedID(item, `${path}[${index}]`));
  unique(result, path);
  return result;
}

function unique(values: string[], path: string): void {
  if (new Set(values).size !== values.length) {
    fail("invalid_schema", `${path} must not contain duplicates.`);
  }
}

function fail(code: string, message: string): never {
  throw new ContractError(code, message);
}

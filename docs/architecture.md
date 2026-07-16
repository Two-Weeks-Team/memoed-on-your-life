# Architecture

Memoed uses explicit boundaries so capture and evidence remain useful even when perception or cloud synthesis is unavailable.

## 1. Capture and storage

Owns imported/captured assets, immutable provenance, lifecycle, deletion, and local persistence. It does not infer what the evidence means.

The iOS implementation uses the privacy-preserving Photos picker for explicit photo selection and AVAudioRecorder for user-initiated audio capture. Media and the versioned JSON manifest are stored under Application Support with data protection enabled. Interrupted perception never deletes the source, so indexing can be retried idempotently.

## 2. Perception and indexing

Apple Speech produces timestamped transcript spans. Apple Vision produces OCR observations and normalized crop coordinates. Adapters report unsupported languages, unavailable assets, partial results, and cancellation without inventing output.

The Speech adapter uses SpeechAnalyzer with SpeechTranscriber and installs a supported on-device language asset only when the person indexes audio. The Vision adapter uses the Swift RecognizeTextRequest API, preserves image orientation, enables automatic language detection, and stores every recognized block with its normalized source region.

## 3. Retrieval and answer synthesis

A deterministic retriever creates bounded evidence packets. A temporal oracle models assertion time, effective time, explicit correction relationships, conflicts, and missing facts. Answer synthesis can render the local result or send the same bounded packet to a server relay for `gpt-5.4-mini` structured output.

Every finalized Speech span and Vision OCR block converts into the same `EvidenceDocument` contract while retaining its source asset, semantic assertion time, source group, and exact coordinate. Ranking is deterministic and uses explicit evidence-count and character budgets; excerpts are never truncated into a synthetic quotation. Default and Challenge searches produce separate immutable packets with separate allowed evidence-ID sets.

The temporal oracle refuses claims with missing or out-of-packet evidence. Explicit correction edges can supersede an earlier claim, but conflicting corrections, equal-time contradictions, and correction cycles remain Ambiguous. Source priority only breaks a tie between equivalent values. Capture time is retained as provenance and never decides which conflicting value is current.

## Invariants

- Later capture time alone never makes a claim current.
- Every material claim points to an allowed evidence ID.
- Challenge receives an independent counterevidence packet, not the first answer's prose.
- Raw audio and full photos are not model payloads.
- Provider failure never overwrites durable local evidence.
- Demo Data and local fixtures are visibly identified.

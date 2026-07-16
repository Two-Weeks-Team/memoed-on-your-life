# Privacy contract

Memoed is designed around user-selected evidence and least disclosure.

- Audio and photos remain on-device by default.
- Speech transcription, OCR, retrieval, and temporal rules are local-first.
- A cloud request requires an explicit user action and contains only bounded transcript spans and selected image crops needed for the question.
- Raw audio and full photo libraries are never sent as model input.
- Requests use `store: false`; the UI and privacy copy do not misrepresent this as Zero Data Retention.
- The server relay enforces model, size, token, time, retry, rate, installation, and total budget limits.
- When relay synthesis is enabled, its iOS client carries only a relay URL and opaque installation identifier; it never contains or sends an OpenAI API key.
- A response is accepted only when every non-Unknown claim cites an evidence ID from the exact request packet.
- Provider responses are size-bounded, schema-validated, and never written to logs by application code.
- Live mode is disabled unless three independent server gates are nonzero and explicit: enable flag, daily budget, and per-flow budget.
- Deleting a memory removes its local asset, index, derived evidence, and associated identifiers.
- Demo Data is synthetic and clearly labeled.

`store: false` is a request-level setting, not a claim of Zero Data Retention. Operators must separately verify provider retention eligibility and deployment-region requirements before enabling live synthesis.

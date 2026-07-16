# Privacy contract

Memoed is designed around user-selected evidence and least disclosure.

- Audio and photos remain on-device by default.
- Speech transcription, OCR, retrieval, and temporal rules are local-first.
- A cloud request requires an explicit user action and contains only bounded transcript spans and selected image crops needed for the question.
- Raw audio and full photo libraries are never sent as model input.
- Requests use `store: false`; the UI and privacy copy do not misrepresent this as Zero Data Retention.
- The server relay enforces model, size, token, time, retry, rate, installation, and total budget limits.
- Deleting a memory removes its local asset, index, derived evidence, and associated identifiers.
- Demo Data is synthetic and clearly labeled.

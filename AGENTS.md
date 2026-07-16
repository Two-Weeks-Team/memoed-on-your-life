# Repository instructions

## Product truth

- Memoed on Your Life is an everyday evidence investigator for facts that change.
- The core loop is capture → evidence → current/superseded/ambiguous/unknown → blind Challenge → exact source.
- Never describe the product as medical diagnosis, legal evidence, or a generic memory chatbot.

## Apple implementation

- Use current Apple first-party documentation before selecting or implementing Speech, Vision, NaturalLanguage, Core ML, Foundation Models, App Intents, Core Spotlight, or Accelerate APIs.
- Keep capture/storage, perception/indexing, and retrieval/answer synthesis separated behind testable adapters.
- Prefer Apple first-party frameworks and semantic SwiftUI components.
- Verify every release path on an iPhone 17 simulator and an iPhone 13 device.

## OpenAI implementation

- The only allowed runtime model is `gpt-5.4-mini` through a server-side Responses API relay.
- Never put an OpenAI API key in the app, source, test fixture, log, screenshot, or repository.
- Require strict structured output, evidence-ID integrity, `store: false`, bounded tokens/calls/retries, and server-enforced cost limits.
- Local fixtures and Demo Data must never be presented as live model results.

## Quality gates

- Run focused tests, full tests, a clean generated-project diff, and the public cleanliness check before committing.
- Treat the real simulator/device screen as the UI acceptance evidence.
- Keep English and Korean, Dynamic Type, VoiceOver, contrast, and Reduce Motion working from the first screen.
- Public documentation must describe only this current product and its current implementation.

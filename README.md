# Memoed on Your Life

Memories change. Memoed finds what changed, challenges the conclusion, and opens the exact evidence behind what is current, superseded, ambiguous, or still unknown.

## Why it is different

A search result can find an old plan. A summary can confidently repeat it. Memoed is designed for the harder question: **what is true now, what changed, and why?**

- **Current / Superseded / Ambiguous / Unknown** instead of an unsupported answer.
- **Blind Challenge** that searches for counterevidence independently.
- **Exact sources** that open the relevant audio interval or image crop.
- **Local-first evidence** with bounded, consented cloud synthesis.

## Current build

The foundation build includes a bilingual, accessible Demo Data walkthrough and typed boundaries for capture, perception, retrieval, and answer synthesis. Demo Data is clearly labeled and runs without permissions or network access.

The production synthesis contract targets only `gpt-5.4-mini` through a server-side Responses API relay. Live cloud behavior remains disabled until its privacy, evidence integrity, and hard cost limits are verified. No API key is bundled in the iOS app.

## Hero walkthrough

1. An earlier audio note says dinner is Thursday at 7:00 PM.
2. A corrected invitation says Friday at 6:30 PM.
3. A newer note says to follow the correction and bring a dairy-free cake.
4. Memoed marks the old plan Superseded, shows the Current plan, and opens each exact source.
5. Challenge independently checks whether contrary evidence should uphold, narrow, revise, or make the answer ambiguous.

## Architecture

```text
Capture & Storage
  → Perception & Indexing (Apple Speech and Vision)
  → Retrieval & Temporal Oracle
  → Answer Synthesis (local fallback or bounded gpt-5.4-mini relay)
  → Citation Navigator & Blind Challenge
```

See [Architecture](docs/architecture.md), [Privacy](docs/privacy.md), and [Validation](docs/validation.md).

## Build

Requirements: Xcode 26.6 and XcodeGen.

```bash
xcodegen generate
xcodebuild \
  -project MemoedOnYourLife.xcodeproj \
  -scheme MemoedOnYourLife \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  test
```

The committed Xcode project is generated from `project.yml`. CI regenerates it and fails if the result differs.

## Build Week use of OpenAI

Codex with GPT-5.6 is used as a substantive engineering partner for architecture, implementation, contract tests, debugging, device verification, and submission review. The app's runtime model contract is separately fixed to `gpt-5.4-mini`.

## License

MIT

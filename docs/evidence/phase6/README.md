# Phase 6 release-candidate evidence

Validated on July 16, 2026 without deploying infrastructure or sending an OpenAI request.

## Automated release gates

- Clean-install iPhone 17 simulator run: 46 passed, 2 microphone-only device checks skipped as designed, 0 failed (48 total).
- Unit coverage: 39 tests, including local source/index/identifier deletion and an interactive CPU envelope for 500 complete local retrieval and Challenge passes.
- UI coverage: 9 definitions, with 7 simulator passes and 2 device-only skips. The active checks cover the complete hero path, system photo picker, Apple Vision OCR, English Accessibility XXXL reachability, standard and maximum-text accessibility audits, tab-bar obstruction, and cold launch.
- Simulator cold launch to first responsive frame: 1.463 s, 1.451 s, and 1.471 s across three measured runs.
- Accessibility: the standard audit and a real Accessibility XXXL + Increase Contrast audit pass. The exact system raw category is `UICTContentSizeCategoryAccessibilityXXXL`; Why, Challenge, Demo Data disclosure, and privacy copy remain reachable. Xcode 26.6's Korean pixel-contrast sub-audit is excluded after reproducibly false-positive results on black label text over an opaque system background; actual Increase Contrast frames were inspected after the UI was moved to semantic label colors and opaque reading surfaces.
- Relay: 25 contract, privacy-deletion, budget, and failure tests passed; generated bindings, TypeScript, deployment dry run, and dependency audit passed with zero known vulnerabilities.
- Public-repository cleanliness, generated-project determinism, workflow lint, secret patterns, local environment files, and origin-language denylist: clean.
- An unsigned Release simulator build passed. A separate optimized Release hero UI test passed 1/1 with testability enabled only for that test invocation; home, answer/Why, exact-source, and final Challenge/privacy frames were inspected.

## Current release surface

The release-candidate completion surface is the iPhone 17 simulator on iOS 26.5. Current acceptance does not depend on a connected physical device. Two microphone-only XCUITests remain compiled and explicitly skip on the simulator; they are not counted as simulator failures.

Previously published device references are historical context, not current-tree release proof:

- [iPhone 13 Why and Challenge comparison](../phase5/iphone13-why-challenge.png)
- [Exact timed transcript persistence](../phase2/iphone13-persisted-transcript.png)

## Cost and privacy gate

Committed live mode, daily spend, and per-flow spend remain zero. Installation deletion is independently callable while synthesis is disabled. It removes installation-linked relay identifiers without erasing anonymous aggregate spend or allowing an in-flight request to escape settlement.

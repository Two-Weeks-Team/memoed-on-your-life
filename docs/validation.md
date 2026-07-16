# Validation

This document separates automated evidence from manual, user-visible device evidence.

## Automated

- `xcodegen generate` produces a byte-identical Xcode project on consecutive runs.
- The iPhone 17 simulator on iOS 26.5 passes three temporal-oracle unit tests.
- The simulator UI test launches the app, loads Demo Data, opens an exact source, dismisses it, runs Blind Challenge, and verifies the result.
- Swift warnings are treated as errors during the verification build.
- A repository cleanliness scan rejects secrets, local environment files, and prohibited provenance language.

## Physical device

An iPhone 13 on iOS 26.5 was installed with the signed development build and reviewed through iPhone Mirroring. The manual touch walkthrough verified:

1. Korean home-screen rendering and visible Demo Data disclosure.
2. Current and superseded conclusions after loading the walkthrough.
3. Exact corrected-invitation evidence in the source sheet.
4. Visible three-step Blind Challenge progress.
5. The final uphold result and reset control.

This is manual user-view evidence, not a claim that the physical-device XCTest runner passed.

## Network and cost

The foundation build performs no live OpenAI API calls. Its runtime contract is fixed to `gpt-5.4-mini`, but cloud synthesis remains disabled until a positive API balance, an explicit spend authorization, privacy checks, and hard server-side limits are all present.

# Validation

This document separates automated evidence from manual, user-visible device evidence.

## Automated

- `xcodegen generate` produces a byte-identical Xcode project on consecutive runs.
- The iPhone 17 simulator on iOS 26.5 passes eleven unit tests, including real Apple Vision OCR, normalized text regions, durable source round trips, visible failure mappings, and an invariant that rejects empty audio transcripts.
- Three simulator UI tests cover the Demo Data challenge flow, the permission-light evidence library, and a synthetic photo selected through the system Photos picker and indexed by Apple Vision.
- Swift warnings are treated as errors during the verification build.
- A repository cleanliness scan rejects secrets, local environment files, and prohibited provenance language.

## Physical device

An iPhone 13 on iOS 26.5 was installed with the signed development build. The manual touch walkthrough verified:

1. Korean home-screen rendering and visible Demo Data disclosure.
2. Current and superseded conclusions after loading the walkthrough.
3. Exact corrected-invitation evidence in the source sheet.
4. Visible three-step Blind Challenge progress.
5. The final uphold result and reset control.

The physical-device XCTest runner also passed these Phase 2 checks:

1. The real microphone records a durable MPEG-4 audio file.
2. The capture screen visibly changes to the recording state.
3. `SpeechAnalyzer` produces finalized transcript text with an exact time range.
4. The transcript detail remains available after terminating and relaunching the app.
5. Apple Vision recognizes a synthetic invitation and returns normalized source regions on the physical device.

The system Photos picker was opened on the physical device without selecting a personal image. [Apple documents](https://support.apple.com/en-us/120421) that the iPhone camera and microphone are unavailable while iPhone Mirroring is active, so microphone capture was driven by physical-device XCUITest after Mirroring was closed.

Evidence:

- [Physical recording state](evidence/phase2/iphone13-recording.png)
- [Timed Speech transcript](evidence/phase2/iphone13-timed-transcript.png)
- [Transcript restored after relaunch](evidence/phase2/iphone13-persisted-transcript.png)

## Network and cost

The foundation build performs no live OpenAI API calls. Its runtime contract is fixed to `gpt-5.4-mini`, but cloud synthesis remains disabled until a positive API balance, an explicit spend authorization, privacy checks, and hard server-side limits are all present.

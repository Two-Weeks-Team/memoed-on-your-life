# Validation

This document separates automated evidence from manual, user-visible device evidence.

## Automated

- `xcodegen generate` produces a byte-identical Xcode project on consecutive runs.
- The iPhone 17 simulator on iOS 26.5 passes thirty-five unit tests, including real Apple Vision OCR, normalized text regions, backward-compatible durable source round trips, visible failure mappings, unified retrieval, a fully evaluated hero fixture, false-citation rejection, unresolved correction rejection, correction-cycle handling, an invariant that rejects empty audio transcripts, relay status mapping, strict response decoding, independent request/response size bounds, and explicit synthesis-origin labeling.
- Three simulator UI tests cover the Demo Data challenge flow, the permission-light evidence library, and a synthetic photo selected through the system Photos picker and indexed by Apple Vision.
- Twenty-one Cloudflare Workers tests validate exact relay contracts, the zero-budget upstream block, strict Structured Outputs fixtures, one-retry bounds, 400/401/429/500/incomplete/refusal/timeout/truncation/model-mismatch handling, evidence-ID integrity, atomic spend reservations, per-flow limits, and circuit breaking.
- Wrangler type generation and a deployment dry run succeed without deploying a Worker or contacting OpenAI.
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

Phase 4 additionally installed a newly signed build and ran the complete Demo flow on the connected iPhone 13. The physical-device accessibility tree found the independent `answer-origin` element, the test passed with no skips, and visual inspection confirmed that **기기 내 결과** appears before the answer card without obscuring the evidence hierarchy.

The system Photos picker was opened on the physical device without selecting a personal image. [Apple documents](https://support.apple.com/en-us/120421) that the iPhone camera and microphone are unavailable while iPhone Mirroring is active, so microphone capture was driven by physical-device XCUITest after Mirroring was closed.

Evidence:

- [Physical recording state](evidence/phase2/iphone13-recording.png)
- [Timed Speech transcript](evidence/phase2/iphone13-timed-transcript.png)
- [Transcript restored after relaunch](evidence/phase2/iphone13-persisted-transcript.png)
- [On-device synthesis origin on iPhone 13](evidence/phase4/iphone13-on-device-origin.png)

## Network and cost

The current build and validation perform no live OpenAI API calls and deploy no infrastructure. Its runtime contract is fixed to `gpt-5.4-mini`; the committed Worker configuration sets live mode, daily spend, and per-flow spend to zero. Live validation remains a separate, blocked gate until a positive API balance and explicit spend authorization exist.

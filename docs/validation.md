# Validation

This document separates the current simulator release gate from historical device evidence and external checks.

## Automated

- `xcodegen generate` produces a byte-identical Xcode project on consecutive runs.
- The iPhone 17 simulator on iOS 26.5 passes thirty-nine unit tests, including real Apple Vision OCR, normalized text regions, backward-compatible durable source round trips, source/index/identifier deletion, visible failure mappings, unified retrieval, a bounded local CPU envelope, a fully evaluated hero fixture, false-citation rejection, unresolved correction rejection, correction-cycle handling, an invariant that rejects empty audio transcripts, relay status mapping, strict response decoding, independent request/response size bounds, installation-identity deletion, and explicit synthesis-origin labeling.
- Nine UI test definitions produce seven simulator passes and two simulator skips for microphone-only historical checks. The active coverage includes the Demo Data challenge flow, the permission-light evidence library, a synthetic photo selected through the system Photos picker and indexed by Apple Vision, English Accessibility XXXL reachability, standard-size structural/Dynamic Type audits, a real Accessibility XXXL layout audit, and a three-iteration cold-launch responsiveness metric.
- CI starts from Large text in light appearance, then reruns both accessibility tests with the simulator's content size set to Accessibility XXXL and Increase Contrast enabled. The Challenge comparison always uses a localization-safe vertical layout, and frame assertions keep the Why explanation, Demo Data disclosure, and privacy pledge above the floating tab bar.
- Increase Contrast screen review exposed and fixed low-contrast origin, status, provenance, changed-value, explanation, and card-material treatments. Xcode 26.6's pixel `contrast` sub-audit is excluded after it reproducibly flagged black semantic-label text on an opaque system background; the remaining automated audit types and actual Increase Contrast screenshots remain mandatory.
- Twenty-five Cloudflare Workers tests validate exact relay contracts, the zero-budget upstream block, strict Structured Outputs fixtures, one-retry bounds, 400/401/429/500/incomplete/refusal/timeout/truncation/model-mismatch handling, evidence-ID integrity, atomic spend reservations, per-flow limits, circuit breaking, and installation-identifier deletion with aggregate spend preservation.
- Wrangler type generation and a deployment dry run succeed without deploying a Worker or contacting OpenAI.
- Swift warnings are treated as errors during the verification build.
- A repository cleanliness scan rejects secrets, local environment files, and prohibited provenance language.
- The clean simulator suite passes 46 tests, skips the two microphone-only device checks, and has zero failures. The measured simulator test build reached its first responsive frame in 1.463, 1.451, and 1.471 seconds across the explicit three-iteration measurement.
- An unsigned Release simulator build succeeds. A separate optimized Release replay, with testability enabled only for that test invocation, passes the complete hero flow and produces inspected home, answer/Why, exact-source, and final Challenge/privacy frames.

## Historical physical-device evidence — not a current release gate

The current release-candidate acceptance path is the iPhone 17 simulator. The records below predate that scope change and remain useful historical evidence; they are not claimed as proof of the exact current tree.

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

Phase 5 reran the signed physical-device flow after adding the explicit Why card and Before/After Challenge comparison. The device test passed with no skip; frame-level UI assertions and visual inspection confirmed that the floating tab bar no longer covers the privacy pledge.

An earlier optimized Release configuration also passed the hero flow on the iPhone 13. Current-tree Release evidence is simulator-based; see the [Phase 6 evidence record](evidence/phase6/README.md).

The system Photos picker was opened on the physical device without selecting a personal image. [Apple documents](https://support.apple.com/en-us/120421) that the iPhone camera and microphone are unavailable while iPhone Mirroring is active, so microphone capture was driven by physical-device XCUITest after Mirroring was closed.

Evidence:

- [Physical recording state](evidence/phase2/iphone13-recording.png)
- [Timed Speech transcript](evidence/phase2/iphone13-timed-transcript.png)
- [Transcript restored after relaunch](evidence/phase2/iphone13-persisted-transcript.png)
- [On-device synthesis origin on iPhone 13](evidence/phase4/iphone13-on-device-origin.png)
- [Accessibility XXXL Challenge comparison](evidence/phase5/simulator-xxxl-challenge.png)
- [iPhone 13 Why and Challenge comparison](evidence/phase5/iphone13-why-challenge.png)

## Network and cost

The current build and validation perform no live OpenAI API calls and deploy no infrastructure. Its runtime contract is fixed to `gpt-5.4-mini`; the committed Worker configuration sets live mode, daily spend, and per-flow spend to zero. Live validation remains a separate, blocked gate until a positive API balance and explicit spend authorization exist.

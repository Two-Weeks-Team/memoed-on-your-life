import Foundation
import XCTest
@testable import MemoedOnYourLife

final class UnifiedRetrievalTests: XCTestCase {
    func testCapturedEvidenceConvertsCoordinatesAndProvenanceIntoUnifiedDocuments() {
        let captured = CapturedEvidence(
            id: UUID(uuidString: "EAF9F8B8-50BA-4A27-86E4-7B0126F8C4EE")!,
            kind: .audio,
            capturedAt: Date(timeIntervalSince1970: 500),
            assertedAt: Date(timeIntervalSince1970: 400),
            sourceGroupID: "dinner-plan",
            originalFilename: "recording.m4a",
            relativePath: "asset.m4a",
            mediaTypeIdentifier: "public.mpeg-4-audio",
            state: .ready,
            ocrBlocks: [],
            transcriptSpans: [AudioTranscriptSpan(
                id: UUID(uuidString: "19DEB04D-8CB8-41D3-BC81-1FDFED0B75CF")!,
                text: "Friday at 6:30 PM",
                startMilliseconds: 1_200,
                endMilliseconds: 2_900
            )],
            failureCode: nil
        )

        let document = captured.retrievalDocuments(tags: ["dinner"]).first

        XCTAssertEqual(document?.evidence.excerpt, "Friday at 6:30 PM")
        XCTAssertEqual(document?.evidence.assertedAt, Date(timeIntervalSince1970: 400))
        XCTAssertEqual(document?.metadata["sourceGroup"], "dinner-plan")
        XCTAssertEqual(
            document?.evidence.coordinate,
            .audioInterval(startMilliseconds: 1_200, endMilliseconds: 2_900)
        )
    }

    func testUnifiedRetrieverFindsTranscriptOCRTagsAndMetadata() {
        let documents = [
            document(
                id: "audio-latest",
                excerpt: "Use the corrected invitation and bring a dairy-free cake.",
                kind: .audioTranscriptSpan,
                tags: ["dinner", "preparation"],
                metadata: ["source": "voice note"]
            ),
            document(
                id: "photo-correction",
                excerpt: "FRIDAY 6:30 PM",
                kind: .imageOCRCrop,
                tags: ["invitation"],
                metadata: ["event": "dinner"]
            ),
            document(
                id: "unrelated",
                excerpt: "Buy detergent",
                kind: .imageOCRCrop,
                tags: ["shopping"],
                metadata: [:]
            )
        ]

        let packet = DeterministicEvidenceRetriever().packet(
            from: documents,
            query: EvidenceQuery(terms: ["dinner", "friday", "cake"]),
            purpose: .defaultAnswer
        )

        XCTAssertEqual(packet.purpose, .defaultAnswer)
        XCTAssertEqual(packet.allowedEvidenceIDs, ["audio-latest", "photo-correction"])
        XCTAssertFalse(packet.allowedEvidenceIDs.contains("unrelated"))
        XCTAssertTrue(packet.items.allSatisfy { !$0.matchedTerms.isEmpty })
    }

    func testBudgetsNeverTruncateOrExceedEvidencePacket() {
        let documents = [
            document(id: "a", excerpt: "dinner friday", kind: .audioTranscriptSpan),
            document(id: "b", excerpt: "dinner correction", kind: .imageOCRCrop),
            document(id: "c", excerpt: "dinner cake", kind: .audioTranscriptSpan)
        ]

        let packet = DeterministicEvidenceRetriever().packet(
            from: documents,
            query: EvidenceQuery(terms: ["dinner"], maxEvidence: 2, maxCharacters: 30),
            purpose: .defaultAnswer
        )

        XCTAssertLessThanOrEqual(packet.items.count, 2)
        XCTAssertLessThanOrEqual(packet.consumedCharacters, 30)
        XCTAssertTrue(documents.contains { $0.evidence.excerpt == packet.items[0].evidence.excerpt })
    }

    func testChallengePacketIsIndependentFromDefaultPacket() {
        let documents = [
            document(
                id: "support",
                excerpt: "Friday at 6:30 PM",
                kind: .imageOCRCrop,
                tags: ["current"]
            ),
            document(
                id: "counter",
                excerpt: "Maybe the dinner is still Thursday",
                kind: .audioTranscriptSpan,
                tags: ["counterevidence"]
            )
        ]
        let retriever = DeterministicEvidenceRetriever()
        let defaultPacket = retriever.packet(
            from: documents,
            query: EvidenceQuery(terms: ["friday", "current"]),
            purpose: .defaultAnswer
        )
        let challengePacket = retriever.packet(
            from: documents,
            query: EvidenceQuery(
                terms: ["thursday", "counterevidence"],
                excludedEvidenceIDs: defaultPacket.allowedEvidenceIDs,
                maxEvidence: 2,
                maxCharacters: 200
            ),
            purpose: .challenge
        )

        XCTAssertEqual(defaultPacket.allowedEvidenceIDs, ["support"])
        XCTAssertEqual(challengePacket.allowedEvidenceIDs, ["counter"])
        XCTAssertTrue(defaultPacket.allowedEvidenceIDs.isDisjoint(with: challengePacket.allowedEvidenceIDs))
        XCTAssertEqual(defaultPacket.purpose, .defaultAnswer)
        XCTAssertEqual(challengePacket.purpose, .challenge)
    }

    func testFalseCitationCannotEnterAdjudication() throws {
        let packet = DeterministicEvidenceRetriever().packet(
            from: [document(
                id: "allowed",
                excerpt: "Friday at 6:30 PM",
                kind: .imageOCRCrop
            )],
            query: EvidenceQuery(terms: ["friday"]),
            purpose: .defaultAnswer
        )
        let injectedClaim = TemporalClaim(
            id: "injected",
            subject: "dinner-time",
            value: "Saturday",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            correctsClaimIDs: [],
            evidenceIDs: ["invented-source"]
        )

        let result = TemporalOracle().adjudicate(
            [injectedClaim],
            subject: "dinner-time",
            allowedEvidenceIDs: packet.allowedEvidenceIDs
        )

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertEqual(result.unknownReason, .unverifiedEvidence)
    }

    func testDemoInvestigationRunsDefaultAndChallengeOnSeparateEvidence() {
        let engine = DemoInvestigationEngine()

        let result = engine.evaluateDefault()
        let challenge = engine.evaluateChallenge(
            excluding: result.defaultPacket.allowedEvidenceIDs
        )

        XCTAssertEqual(result.dinner.verdict, .current)
        XCTAssertEqual(result.dinner.currentClaimID, "latest-confirmation")
        XCTAssertEqual(result.preparation.verdict, .current)
        XCTAssertEqual(challenge.purpose, .challenge)
        XCTAssertEqual(challenge.allowedEvidenceIDs, ["counter-note"])
        XCTAssertTrue(
            result.defaultPacket.allowedEvidenceIDs.isDisjoint(
                with: challenge.allowedEvidenceIDs
            )
        )
    }

    func testHeroRetrievalAndChallengeRemainWithinAnInteractiveCPUEnvelope() {
        let engine = DemoInvestigationEngine()
        let clock = ContinuousClock()
        var lastChallengeCount = 0

        let duration = clock.measure {
            for _ in 0 ..< 500 {
                let result = engine.evaluateDefault()
                let challenge = engine.evaluateChallenge(
                    excluding: result.defaultPacket.allowedEvidenceIDs
                )
                lastChallengeCount = challenge.items.count
            }
        }

        XCTAssertGreaterThan(lastChallengeCount, 0)
        XCTAssertLessThan(
            duration,
            .seconds(3),
            "Five hundred local retrieval and Challenge passes must stay inside a generous interactive CPU envelope."
        )
    }

    private func document(
        id: String,
        excerpt: String,
        kind: EvidenceSourceKind,
        tags: Set<String> = [],
        metadata: [String: String] = [:]
    ) -> EvidenceDocument {
        let coordinate: EvidenceCoordinate = switch kind {
        case .audioTranscriptSpan:
            .audioInterval(startMilliseconds: 0, endMilliseconds: 1_000)
        case .imageOCRCrop:
            .normalizedCrop(x: 0.1, y: 0.1, width: 0.5, height: 0.2)
        }
        return EvidenceDocument(
            evidence: EvidenceSnippet(
                id: id,
                sourceKind: kind,
                excerpt: excerpt,
                capturedAt: Date(timeIntervalSince1970: 100),
                assertedAt: nil,
                coordinate: coordinate
            ),
            tags: tags,
            metadata: metadata
        )
    }
}

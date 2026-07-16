import Foundation

struct DemoInvestigationResult: Equatable, Sendable {
    let defaultPacket: EvidencePacket
    let dinner: TemporalAdjudication
    let preparation: TemporalAdjudication
}

struct DemoInvestigationEngine: Sendable {
    private let retriever = DeterministicEvidenceRetriever()
    private let oracle = TemporalOracle()

    func evaluateDefault() -> DemoInvestigationResult {
        let packet = retriever.packet(
            from: Self.documents,
            query: EvidenceQuery(
                terms: ["dinner", "friday", "cake", "correction"],
                maxEvidence: 6,
                maxCharacters: 1_200
            ),
            purpose: .defaultAnswer
        )
        return DemoInvestigationResult(
            defaultPacket: packet,
            dinner: oracle.adjudicate(
                Self.dinnerClaims,
                subject: "dinner-time",
                allowedEvidenceIDs: packet.allowedEvidenceIDs
            ),
            preparation: oracle.adjudicate(
                Self.preparationClaims,
                subject: "preparation",
                allowedEvidenceIDs: packet.allowedEvidenceIDs
            )
        )
    }

    func evaluateChallenge(excluding defaultEvidenceIDs: Set<String>) -> EvidencePacket {
        retriever.packet(
            from: Self.documents,
            query: EvidenceQuery(
                terms: ["thursday", "original", "outdated", "counterevidence"],
                excludedEvidenceIDs: defaultEvidenceIDs,
                maxEvidence: 3,
                maxCharacters: 600
            ),
            purpose: .challenge
        )
    }

    private static let documents: [EvidenceDocument] = [
        document(
            id: "audio-earlier",
            excerpt: "Dinner is Thursday at 7:00 PM.",
            kind: .audioTranscriptSpan,
            tags: ["dinner", "earlier"]
        ),
        document(
            id: "photo-correction",
            excerpt: "Corrected invitation: Friday at 6:30 PM.",
            kind: .imageOCRCrop,
            tags: ["dinner", "invitation", "correction"]
        ),
        document(
            id: "audio-latest",
            excerpt: "Use the Friday correction and bring a dairy-free cake.",
            kind: .audioTranscriptSpan,
            tags: ["dinner", "preparation", "cake"]
        ),
        document(
            id: "counter-note",
            excerpt: "The original Thursday plan was marked outdated.",
            kind: .audioTranscriptSpan,
            tags: ["counterevidence", "original"]
        )
    ]

    private static let dinnerClaims: [TemporalClaim] = [
        TemporalClaim(
            id: "earlier-dinner",
            subject: "dinner-time",
            value: "Thursday 7:00 PM",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 110),
            correctsClaimIDs: [],
            evidenceIDs: ["audio-earlier"]
        ),
        TemporalClaim(
            id: "invitation-correction",
            subject: "dinner-time",
            value: "Friday 6:30 PM",
            assertedAt: Date(timeIntervalSince1970: 200),
            effectiveAt: Date(timeIntervalSince1970: 400),
            sourceCapturedAt: Date(timeIntervalSince1970: 210),
            correctsClaimIDs: ["earlier-dinner"],
            evidenceIDs: ["photo-correction"],
            sourcePriority: .explicitCorrection
        ),
        TemporalClaim(
            id: "latest-confirmation",
            subject: "dinner-time",
            value: "Friday 6:30 PM",
            assertedAt: Date(timeIntervalSince1970: 300),
            effectiveAt: Date(timeIntervalSince1970: 400),
            sourceCapturedAt: Date(timeIntervalSince1970: 310),
            correctsClaimIDs: [],
            evidenceIDs: ["audio-latest"]
        )
    ]

    private static let preparationClaims: [TemporalClaim] = [
        TemporalClaim(
            id: "cake-preparation",
            subject: "preparation",
            value: "Bring a dairy-free cake",
            assertedAt: Date(timeIntervalSince1970: 300),
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 310),
            correctsClaimIDs: [],
            evidenceIDs: ["audio-latest"]
        )
    ]

    private static func document(
        id: String,
        excerpt: String,
        kind: EvidenceSourceKind,
        tags: Set<String>
    ) -> EvidenceDocument {
        let coordinate: EvidenceCoordinate = switch kind {
        case .audioTranscriptSpan:
            .audioInterval(startMilliseconds: 0, endMilliseconds: 4_000)
        case .imageOCRCrop:
            .normalizedCrop(x: 0.08, y: 0.18, width: 0.84, height: 0.22)
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
            metadata: ["fixture": "demo-data"]
        )
    }
}

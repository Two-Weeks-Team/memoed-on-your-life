import Foundation

enum RetrievalPurpose: String, Codable, Equatable, Sendable {
    case defaultAnswer
    case challenge
}

struct EvidenceDocument: Identifiable, Hashable, Sendable {
    let evidence: EvidenceSnippet
    let tags: Set<String>
    let metadata: [String: String]

    var id: String { evidence.id }
}

struct EvidenceQuery: Equatable, Sendable {
    let terms: [String]
    let excludedEvidenceIDs: Set<String>
    let maxEvidence: Int
    let maxCharacters: Int

    init(
        terms: [String],
        excludedEvidenceIDs: Set<String> = [],
        maxEvidence: Int = 6,
        maxCharacters: Int = 2_400
    ) {
        self.terms = terms
        self.excludedEvidenceIDs = excludedEvidenceIDs
        self.maxEvidence = max(maxEvidence, 0)
        self.maxCharacters = max(maxCharacters, 0)
    }
}

struct RankedEvidence: Identifiable, Hashable, Sendable {
    let evidence: EvidenceSnippet
    let score: Int
    let matchedTerms: Set<String>

    var id: String { evidence.id }
}

struct EvidencePacket: Equatable, Sendable {
    let purpose: RetrievalPurpose
    let queryTerms: [String]
    let items: [RankedEvidence]
    let consumedCharacters: Int

    var allowedEvidenceIDs: Set<String> {
        Set(items.map(\.id))
    }
}

struct DeterministicEvidenceRetriever: Sendable {
    func packet(
        from documents: [EvidenceDocument],
        query: EvidenceQuery,
        purpose: RetrievalPurpose
    ) -> EvidencePacket {
        let normalizedTerms = Self.normalizedTerms(query.terms)
        let ranked = documents.compactMap { document -> RankedEvidence? in
            guard !query.excludedEvidenceIDs.contains(document.id) else { return nil }
            let excerpt = Self.normalize(document.evidence.excerpt)
            let tags = Set(document.tags.map(Self.normalize))
            let metadata = document.metadata
                .flatMap { [Self.normalize($0.key), Self.normalize($0.value)] }
                .joined(separator: " ")

            var score = 0
            var matches: Set<String> = []
            for term in normalizedTerms {
                if excerpt.contains(term) {
                    score += 8
                    matches.insert(term)
                }
                if tags.contains(term) {
                    score += 5
                    matches.insert(term)
                }
                if metadata.contains(term) {
                    score += 3
                    matches.insert(term)
                }
            }
            guard score > 0 else { return nil }
            return RankedEvidence(evidence: document.evidence, score: score, matchedTerms: matches)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.id < $1.id
        }

        var items: [RankedEvidence] = []
        var consumedCharacters = 0
        for item in ranked where items.count < query.maxEvidence {
            let itemCharacters = item.evidence.excerpt.count
            guard consumedCharacters + itemCharacters <= query.maxCharacters else { continue }
            items.append(item)
            consumedCharacters += itemCharacters
        }

        return EvidencePacket(
            purpose: purpose,
            queryTerms: normalizedTerms,
            items: items,
            consumedCharacters: consumedCharacters
        )
    }

    private static func normalizedTerms(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .flatMap { normalize($0).split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func normalize(_ value: String) -> String {
        let folded = value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        return String(folded.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CapturedEvidence {
    func retrievalDocuments(
        tags: Set<String> = [],
        metadata: [String: String] = [:]
    ) -> [EvidenceDocument] {
        var sourceMetadata = metadata
        if let sourceGroupID {
            sourceMetadata["sourceGroup"] = sourceGroupID
        }
        sourceMetadata["mediaType"] = mediaTypeIdentifier

        switch kind {
        case .audio:
            return transcriptSpans.map { span in
                EvidenceDocument(
                    evidence: EvidenceSnippet(
                        id: "\(id.uuidString):transcript:\(span.id.uuidString)",
                        sourceKind: .audioTranscriptSpan,
                        excerpt: span.text,
                        capturedAt: capturedAt,
                        assertedAt: assertedAt,
                        coordinate: .audioInterval(
                            startMilliseconds: span.startMilliseconds,
                            endMilliseconds: span.endMilliseconds
                        )
                    ),
                    tags: tags,
                    metadata: sourceMetadata
                )
            }
        case .photo:
            return ocrBlocks.map { block in
                EvidenceDocument(
                    evidence: EvidenceSnippet(
                        id: "\(id.uuidString):ocr:\(block.id.uuidString)",
                        sourceKind: .imageOCRCrop,
                        excerpt: block.text,
                        capturedAt: capturedAt,
                        assertedAt: assertedAt,
                        coordinate: .normalizedCrop(
                            x: block.crop.x,
                            y: block.crop.y,
                            width: block.crop.width,
                            height: block.crop.height
                        )
                    ),
                    tags: tags,
                    metadata: sourceMetadata
                )
            }
        }
    }
}

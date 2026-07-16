import Foundation

enum EvidenceVerdict: String, Codable, CaseIterable, Sendable {
    case current
    case superseded
    case ambiguous
    case unknown
}

enum EvidenceSourceKind: String, Codable, Sendable {
    case audioTranscriptSpan
    case imageOCRCrop
}

enum EvidenceCoordinate: Hashable, Sendable {
    case audioInterval(startMilliseconds: Int, endMilliseconds: Int)
    case normalizedCrop(x: Double, y: Double, width: Double, height: Double)
}

struct EvidenceSnippet: Identifiable, Hashable, Sendable {
    let id: String
    let sourceKind: EvidenceSourceKind
    let excerpt: String
    let capturedAt: Date
    let assertedAt: Date?
    let coordinate: EvidenceCoordinate
}

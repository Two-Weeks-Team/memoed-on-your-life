import Foundation

enum CapturedEvidenceKind: String, Codable, CaseIterable, Sendable {
    case audio
    case photo
}

enum CapturedEvidenceState: String, Codable, Sendable {
    case queued
    case indexing
    case ready
    case failed
}

enum EvidenceFailureCode: String, Codable, Equatable, Sendable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case photoUnavailable
    case unsupportedLanguage
    case speechAssetsUnavailable
    case unreadableMedia
    case processingFailed
}

struct NormalizedCrop: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        let normalizedX = min(max(x, 0), 1)
        let normalizedY = min(max(y, 0), 1)
        self.x = normalizedX
        self.y = normalizedY
        self.width = min(max(width, 0), 1 - normalizedX)
        self.height = min(max(height, 0), 1 - normalizedY)
    }
}

struct OCRTextBlock: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let text: String
    let confidence: Float
    let crop: NormalizedCrop
    let languageIdentifiers: [String]
}

struct AudioTranscriptSpan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let text: String
    let startMilliseconds: Int
    let endMilliseconds: Int
}

struct CapturedEvidence: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: CapturedEvidenceKind
    let capturedAt: Date
    let originalFilename: String
    let relativePath: String
    let mediaTypeIdentifier: String
    var state: CapturedEvidenceState
    var ocrBlocks: [OCRTextBlock]
    var transcriptSpans: [AudioTranscriptSpan]
    var failureCode: EvidenceFailureCode?

    var searchableText: String {
        switch kind {
        case .photo:
            ocrBlocks.map(\.text).joined(separator: "\n")
        case .audio:
            transcriptSpans.map(\.text).joined(separator: " ")
        }
    }
}

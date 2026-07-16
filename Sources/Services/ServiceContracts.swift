import Foundation

struct CapturedAsset: Identifiable, Hashable, Sendable {
    let id: String
    let localURL: URL
    let capturedAt: Date
    let kind: EvidenceSourceKind
}

protocol CaptureService: Sendable {
    func captureAudio() async throws -> CapturedAsset
    func importPhoto() async throws -> CapturedAsset
}

protocol PerceptionService: Sendable {
    func index(asset: CapturedAsset) async throws -> [EvidenceSnippet]
}

protocol RetrievalService: Sendable {
    func evidence(for question: String, limit: Int) async throws -> [EvidenceSnippet]
    func counterevidence(for structuredClaim: String, limit: Int) async throws -> [EvidenceSnippet]
}

enum AnswerSynthesisMode: String, Sendable {
    case standard
    case challenge
}

struct SynthesizedClaim: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let verdict: EvidenceVerdict
    let evidenceIDs: [String]
}

struct SynthesizedAnswer: Equatable, Sendable {
    let verdict: EvidenceVerdict
    let answer: String
    let claims: [SynthesizedClaim]
    let why: String
}

protocol AnswerSynthesisService: Sendable {
    func synthesize(
        question: String,
        evidence: [EvidenceSnippet],
        mode: AnswerSynthesisMode
    ) async throws -> SynthesizedAnswer
}

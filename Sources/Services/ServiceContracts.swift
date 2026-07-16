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

enum AnswerSynthesisMode: String, Codable, Sendable {
    case standard
    case challenge
}

enum SynthesisOrigin: String, Codable, Equatable, Sendable {
    case onDevice
    case cloud

    var localizationKey: String {
        switch self {
        case .onDevice: "synthesis.origin.on_device"
        case .cloud: "synthesis.origin.cloud"
        }
    }
}

enum ChallengeDisposition: String, Codable, Equatable, Sendable {
    case notRun = "not_run"
    case upheld
    case narrowed
    case revised
    case ambiguous
}

struct SynthesizedClaim: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let text: String
    let verdict: EvidenceVerdict
    let evidenceIDs: [String]
}

struct SynthesizedAnswer: Codable, Equatable, Sendable {
    let verdict: EvidenceVerdict
    let answer: String
    let claims: [SynthesizedClaim]
    let why: String
    let missingEvidence: [String]
    let challengeDisposition: ChallengeDisposition
    let origin: SynthesisOrigin
}

protocol AnswerSynthesisService: Sendable {
    func synthesize(
        question: String,
        evidence: [EvidenceSnippet],
        mode: AnswerSynthesisMode
    ) async throws -> SynthesizedAnswer
}

struct OnDeviceAnswerSynthesisService: AnswerSynthesisService {
    func synthesize(
        question: String,
        evidence: [EvidenceSnippet],
        mode: AnswerSynthesisMode
    ) async throws -> SynthesizedAnswer {
        guard !evidence.isEmpty else {
            return SynthesizedAnswer(
                verdict: .unknown,
                answer: "No local evidence answers this question yet.",
                claims: [],
                why: "The on-device evidence packet is empty.",
                missingEvidence: ["A bounded evidence packet is required."],
                challengeDisposition: mode == .challenge ? .ambiguous : .notRun,
                origin: .onDevice
            )
        }

        let claims = evidence.map { item in
            SynthesizedClaim(
                id: "local:\(item.id)",
                text: item.excerpt,
                verdict: mode == .challenge ? .ambiguous : .current,
                evidenceIDs: [item.id]
            )
        }
        return SynthesizedAnswer(
            verdict: mode == .challenge ? .ambiguous : .current,
            answer: evidence[0].excerpt,
            claims: claims,
            why: "This deterministic on-device result is limited to the selected evidence packet.",
            missingEvidence: [],
            challengeDisposition: mode == .challenge ? .ambiguous : .notRun,
            origin: .onDevice
        )
    }
}

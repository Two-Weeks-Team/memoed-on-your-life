import Foundation
import Observation

enum DemoSource: String, Identifiable, Sendable {
    case earlierAudio
    case correctedInvitation
    case latestAudio

    var id: String { rawValue }
}

@MainActor
@Observable
final class HomeModel {
    enum State: Equatable {
        case ready
        case answer
        case challenging(step: Int)
        case challenged
    }

    var state: State = .ready
    var selectedSource: DemoSource?
    private(set) var defaultResult: DemoInvestigationResult?
    private(set) var challengePacket: EvidencePacket?

    private let investigation = DemoInvestigationEngine()

    var showsAnswer: Bool {
        state != .ready
    }

    var challengeStep: Int? {
        guard case let .challenging(step) = state else { return nil }
        return step
    }

    var challengeComplete: Bool {
        state == .challenged
    }

    func loadDemo() {
        let result = investigation.evaluateDefault()
        defaultResult = result
        challengePacket = nil
        state = result.dinner.verdict == .current
            && result.preparation.verdict == .current
            ? .answer
            : .ready
    }

    func loadChallengedDemo() {
        loadDemo()
        guard let defaultResult else { return }
        challengePacket = investigation.evaluateChallenge(
            excluding: defaultResult.defaultPacket.allowedEvidenceIDs
        )
        state = .challenged
    }

    func reset() {
        selectedSource = nil
        defaultResult = nil
        challengePacket = nil
        state = .ready
    }

    func runChallenge() async {
        guard state == .answer else { return }
        for step in 0..<3 {
            guard !Task.isCancelled else { return }
            state = .challenging(step: step)
            try? await Task.sleep(for: .milliseconds(550))
        }
        guard !Task.isCancelled else { return }
        guard let defaultResult else { return }
        challengePacket = investigation.evaluateChallenge(
            excluding: defaultResult.defaultPacket.allowedEvidenceIDs
        )
        state = .challenged
    }
}

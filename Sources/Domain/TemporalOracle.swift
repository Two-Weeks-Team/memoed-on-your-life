import Foundation

struct TemporalClaim: Identifiable, Hashable, Sendable {
    let id: String
    let subject: String
    let value: String
    let assertedAt: Date
    let effectiveAt: Date?
    let correctsClaimIDs: Set<String>
}

struct TemporalClaimResult: Identifiable, Equatable, Sendable {
    let id: String
    let status: EvidenceVerdict
}

struct TemporalAdjudication: Equatable, Sendable {
    let verdict: EvidenceVerdict
    let currentClaimID: String?
    let claimResults: [TemporalClaimResult]
}

struct TemporalOracle: Sendable {
    func adjudicate(_ claims: [TemporalClaim], subject: String) -> TemporalAdjudication {
        let scopedClaims = claims.filter { $0.subject == subject }
        guard !scopedClaims.isEmpty else {
            return TemporalAdjudication(
                verdict: .unknown,
                currentClaimID: nil,
                claimResults: []
            )
        }

        let knownIDs = Set(scopedClaims.map(\.id))
        let supersededIDs = Set(
            scopedClaims.flatMap { claim in
                claim.correctsClaimIDs.intersection(knownIDs)
            }
        )
        let candidates = scopedClaims.filter { !supersededIDs.contains($0.id) }
        let candidateValues = Set(candidates.map(\.value))

        let verdict: EvidenceVerdict
        let currentClaimID: String?
        if candidates.isEmpty {
            verdict = .unknown
            currentClaimID = nil
        } else if candidateValues.count > 1 {
            verdict = .ambiguous
            currentClaimID = nil
        } else {
            verdict = .current
            currentClaimID = candidates.max(by: preferredClaimOrder)?.id
        }

        let results = scopedClaims.map { claim in
            TemporalClaimResult(
                id: claim.id,
                status: supersededIDs.contains(claim.id) ? .superseded : verdictForCandidate(
                    claimID: claim.id,
                    currentClaimID: currentClaimID,
                    overallVerdict: verdict
                )
            )
        }

        return TemporalAdjudication(
            verdict: verdict,
            currentClaimID: currentClaimID,
            claimResults: results
        )
    }

    private func preferredClaimOrder(_ lhs: TemporalClaim, _ rhs: TemporalClaim) -> Bool {
        let lhsTime = lhs.effectiveAt ?? lhs.assertedAt
        let rhsTime = rhs.effectiveAt ?? rhs.assertedAt
        if lhsTime == rhsTime {
            return lhs.assertedAt < rhs.assertedAt
        }
        return lhsTime < rhsTime
    }

    private func verdictForCandidate(
        claimID: String,
        currentClaimID: String?,
        overallVerdict: EvidenceVerdict
    ) -> EvidenceVerdict {
        switch overallVerdict {
        case .current:
            return claimID == currentClaimID ? .current : .ambiguous
        case .ambiguous:
            return .ambiguous
        case .unknown:
            return .unknown
        case .superseded:
            return .superseded
        }
    }
}

import Foundation

enum TemporalSourcePriority: Int, Codable, CaseIterable, Sendable {
    case contextual = 0
    case direct = 1
    case explicitCorrection = 2
}

enum TemporalUnknownReason: String, Codable, Equatable, Sendable {
    case noMatchingClaims
    case missingEvidence
    case unverifiedEvidence
    case unresolvedCorrectionReference
    case noCurrentCandidate
}

struct TemporalClaim: Identifiable, Hashable, Sendable {
    let id: String
    let subject: String
    let value: String
    let assertedAt: Date?
    let effectiveAt: Date?
    let sourceCapturedAt: Date?
    let correctsClaimIDs: Set<String>
    let evidenceIDs: Set<String>
    let sourcePriority: TemporalSourcePriority

    init(
        id: String,
        subject: String,
        value: String,
        assertedAt: Date?,
        effectiveAt: Date?,
        sourceCapturedAt: Date? = nil,
        correctsClaimIDs: Set<String>,
        evidenceIDs: Set<String> = [],
        sourcePriority: TemporalSourcePriority = .direct
    ) {
        self.id = id
        self.subject = subject
        self.value = value
        self.assertedAt = assertedAt
        self.effectiveAt = effectiveAt
        self.sourceCapturedAt = sourceCapturedAt ?? assertedAt
        self.correctsClaimIDs = correctsClaimIDs
        self.evidenceIDs = evidenceIDs
        self.sourcePriority = sourcePriority
    }
}

struct TemporalClaimResult: Identifiable, Equatable, Sendable {
    let id: String
    let status: EvidenceVerdict
    let evidenceIDs: Set<String>
}

struct TemporalAdjudication: Equatable, Sendable {
    let verdict: EvidenceVerdict
    let currentClaimID: String?
    let claimResults: [TemporalClaimResult]
    let supportingEvidenceIDs: Set<String>
    let unknownReason: TemporalUnknownReason?
}

struct TemporalOracle: Sendable {
    func adjudicate(
        _ claims: [TemporalClaim],
        subject: String,
        allowedEvidenceIDs: Set<String>? = nil
    ) -> TemporalAdjudication {
        let scopedClaims = claims
            .filter { $0.subject == subject }
            .sorted { $0.id < $1.id }
        guard !scopedClaims.isEmpty else {
            return unknown(claims: [], reason: .noMatchingClaims)
        }

        guard scopedClaims.allSatisfy({ !$0.evidenceIDs.isEmpty }) else {
            return unknown(claims: scopedClaims, reason: .missingEvidence)
        }
        if let allowedEvidenceIDs,
           scopedClaims.contains(where: { !$0.evidenceIDs.isSubset(of: allowedEvidenceIDs) }) {
            return unknown(claims: scopedClaims, reason: .unverifiedEvidence)
        }

        let knownIDs = Set(scopedClaims.map(\.id))
        if scopedClaims.contains(where: { !$0.correctsClaimIDs.isSubset(of: knownIDs) }) {
            return unknown(claims: scopedClaims, reason: .unresolvedCorrectionReference)
        }
        let correctionGraph = Dictionary(
            uniqueKeysWithValues: scopedClaims.map { claim in
                (claim.id, claim.correctsClaimIDs.intersection(knownIDs))
            }
        )
        if containsCycle(in: correctionGraph) {
            return TemporalAdjudication(
                verdict: .ambiguous,
                currentClaimID: nil,
                claimResults: scopedClaims.map {
                    TemporalClaimResult(
                        id: $0.id,
                        status: .ambiguous,
                        evidenceIDs: $0.evidenceIDs
                    )
                },
                supportingEvidenceIDs: Set(scopedClaims.flatMap(\.evidenceIDs)),
                unknownReason: nil
            )
        }

        let supersededIDs = Set(correctionGraph.values.flatMap { $0 })
        let candidates = scopedClaims.filter { !supersededIDs.contains($0.id) }
        guard !candidates.isEmpty else {
            return unknown(claims: scopedClaims, reason: .noCurrentCandidate)
        }

        let candidateValues = Set(candidates.map(\.value))
        let verdict: EvidenceVerdict = candidateValues.count == 1 ? .current : .ambiguous
        let currentClaimID = verdict == .current
            ? candidates.max(by: preferredClaimOrder)?.id
            : nil
        let candidateIDs = Set(candidates.map(\.id))
        let results = scopedClaims.map { claim in
            let status: EvidenceVerdict
            if supersededIDs.contains(claim.id) {
                status = .superseded
            } else if verdict == .current && candidateIDs.contains(claim.id) {
                status = .current
            } else {
                status = .ambiguous
            }
            return TemporalClaimResult(
                id: claim.id,
                status: status,
                evidenceIDs: claim.evidenceIDs
            )
        }

        return TemporalAdjudication(
            verdict: verdict,
            currentClaimID: currentClaimID,
            claimResults: results,
            supportingEvidenceIDs: Set(candidates.flatMap(\.evidenceIDs)),
            unknownReason: nil
        )
    }

    private func unknown(
        claims: [TemporalClaim],
        reason: TemporalUnknownReason
    ) -> TemporalAdjudication {
        TemporalAdjudication(
            verdict: .unknown,
            currentClaimID: nil,
            claimResults: claims.map {
                TemporalClaimResult(id: $0.id, status: .unknown, evidenceIDs: [])
            },
            supportingEvidenceIDs: [],
            unknownReason: reason
        )
    }

    private func preferredClaimOrder(_ lhs: TemporalClaim, _ rhs: TemporalClaim) -> Bool {
        let lhsTime = lhs.effectiveAt ?? lhs.assertedAt
        let rhsTime = rhs.effectiveAt ?? rhs.assertedAt
        if lhsTime != rhsTime {
            switch (lhsTime, rhsTime) {
            case let (lhsTime?, rhsTime?): return lhsTime < rhsTime
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): break
            }
        }
        if lhs.assertedAt != rhs.assertedAt {
            switch (lhs.assertedAt, rhs.assertedAt) {
            case let (lhsTime?, rhsTime?): return lhsTime < rhsTime
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): break
            }
        }
        if lhs.sourcePriority != rhs.sourcePriority {
            return lhs.sourcePriority.rawValue < rhs.sourcePriority.rawValue
        }
        return lhs.id < rhs.id
    }

    private func containsCycle(in graph: [String: Set<String>]) -> Bool {
        enum VisitState {
            case visiting
            case visited
        }

        var states: [String: VisitState] = [:]

        func visit(_ node: String) -> Bool {
            if states[node] == .visiting { return true }
            if states[node] == .visited { return false }
            states[node] = .visiting
            for neighbor in graph[node] ?? [] where visit(neighbor) {
                return true
            }
            states[node] = .visited
            return false
        }

        return graph.keys.contains(where: visit)
    }
}

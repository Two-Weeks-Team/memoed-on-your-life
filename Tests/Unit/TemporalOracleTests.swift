import Foundation
import XCTest
@testable import MemoedOnYourLife

final class TemporalOracleTests: XCTestCase {
    func testExplicitCorrectionSupersedesEarlierClaim() {
        let earlier = TemporalClaim(
            id: "earlier",
            subject: "dinner-time",
            value: "Thursday 7:00 PM",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-earlier"]
        )
        let correction = TemporalClaim(
            id: "correction",
            subject: "dinner-time",
            value: "Friday 6:30 PM",
            assertedAt: Date(timeIntervalSince1970: 200),
            effectiveAt: nil,
            correctsClaimIDs: ["earlier"],
            evidenceIDs: ["evidence-correction"],
            sourcePriority: .explicitCorrection
        )

        let result = TemporalOracle().adjudicate([earlier, correction], subject: "dinner-time")

        XCTAssertEqual(result.verdict, .current)
        XCTAssertEqual(result.currentClaimID, "correction")
        XCTAssertEqual(result.supportingEvidenceIDs, ["evidence-correction"])
        XCTAssertNil(result.unknownReason)
        XCTAssertTrue(result.claimResults.allSatisfy { !$0.evidenceIDs.isEmpty })
        XCTAssertEqual(
            result.claimResults.first(where: { $0.id == "earlier" })?.status,
            .superseded
        )
    }

    func testLaterCaptureAloneDoesNotResolveContradiction() {
        let first = TemporalClaim(
            id: "first",
            subject: "location",
            value: "Cafe",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 500),
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-first"]
        )
        let later = TemporalClaim(
            id: "later",
            subject: "location",
            value: "Park",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 900),
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-later-capture"]
        )

        let result = TemporalOracle().adjudicate([first, later], subject: "location")

        XCTAssertEqual(result.verdict, .ambiguous)
        XCTAssertNil(result.currentClaimID)
        XCTAssertEqual(
            result.supportingEvidenceIDs,
            ["evidence-first", "evidence-later-capture"]
        )
    }

    func testMissingSubjectIsUnknown() {
        let result = TemporalOracle().adjudicate([], subject: "unknown")

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertNil(result.currentClaimID)
        XCTAssertTrue(result.claimResults.isEmpty)
        XCTAssertEqual(result.unknownReason, .noMatchingClaims)
    }

    func testCycleIsAmbiguousInsteadOfInventingAWinner() {
        let first = claim(
            id: "first",
            value: "Cafe",
            corrects: ["second"],
            evidenceID: "evidence-first"
        )
        let second = claim(
            id: "second",
            value: "Park",
            corrects: ["first"],
            evidenceID: "evidence-second"
        )

        let result = TemporalOracle().adjudicate([first, second], subject: "location")

        XCTAssertEqual(result.verdict, .ambiguous)
        XCTAssertNil(result.currentClaimID)
        XCTAssertTrue(result.claimResults.allSatisfy { $0.status == .ambiguous })
        XCTAssertNil(result.unknownReason)
    }

    func testUnresolvedCorrectionReferenceProducesHonestUnknown() {
        let correction = claim(
            id: "correction",
            value: "Friday",
            corrects: ["missing-original"],
            evidenceID: "evidence-correction"
        )

        let result = TemporalOracle().adjudicate([correction], subject: "location")

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertEqual(result.unknownReason, .unresolvedCorrectionReference)
        XCTAssertTrue(result.supportingEvidenceIDs.isEmpty)
    }

    func testConflictingCorrectionsRemainAmbiguous() {
        let original = claim(
            id: "original",
            value: "Thursday",
            evidenceID: "evidence-original"
        )
        let friday = claim(
            id: "friday",
            value: "Friday",
            corrects: ["original"],
            evidenceID: "evidence-friday"
        )
        let saturday = claim(
            id: "saturday",
            value: "Saturday",
            corrects: ["original"],
            evidenceID: "evidence-saturday"
        )

        let result = TemporalOracle().adjudicate(
            [original, friday, saturday],
            subject: "location"
        )

        XCTAssertEqual(result.verdict, .ambiguous)
        XCTAssertNil(result.currentClaimID)
        XCTAssertEqual(result.supportingEvidenceIDs, ["evidence-friday", "evidence-saturday"])
    }

    func testEvidenceOutsidePacketProducesHonestUnknown() {
        let claim = claim(id: "candidate", value: "Friday", evidenceID: "not-in-packet")

        let result = TemporalOracle().adjudicate(
            [claim],
            subject: "location",
            allowedEvidenceIDs: ["allowed-evidence"]
        )

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertEqual(result.unknownReason, .unverifiedEvidence)
        XCTAssertTrue(result.supportingEvidenceIDs.isEmpty)
    }

    func testMissingEvidenceProducesHonestUnknown() {
        let claim = TemporalClaim(
            id: "candidate",
            subject: "location",
            value: "Friday",
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            correctsClaimIDs: []
        )

        let result = TemporalOracle().adjudicate([claim], subject: "location")

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertEqual(result.unknownReason, .missingEvidence)
    }

    func testMissingSemanticTimesDoNotResolveAConflict() {
        let first = TemporalClaim(
            id: "first",
            subject: "location",
            value: "Cafe",
            assertedAt: nil,
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 500),
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-first"]
        )
        let second = TemporalClaim(
            id: "second",
            subject: "location",
            value: "Park",
            assertedAt: nil,
            effectiveAt: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 900),
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-second"]
        )

        let result = TemporalOracle().adjudicate([first, second], subject: "location")

        XCTAssertEqual(result.verdict, .ambiguous)
        XCTAssertNil(result.currentClaimID)
    }

    func testAdjudicationIsInvariantToInputOrder() {
        let original = claim(
            id: "original",
            value: "Thursday",
            evidenceID: "evidence-original"
        )
        let correction = claim(
            id: "correction",
            value: "Friday",
            corrects: ["original"],
            evidenceID: "evidence-correction"
        )
        let confirmation = claim(
            id: "confirmation",
            value: "Friday",
            evidenceID: "evidence-confirmation"
        )
        let permutations = [
            [original, correction, confirmation],
            [original, confirmation, correction],
            [correction, original, confirmation],
            [correction, confirmation, original],
            [confirmation, original, correction],
            [confirmation, correction, original]
        ]

        let results = permutations.map {
            TemporalOracle().adjudicate($0, subject: "location")
        }

        XCTAssertTrue(results.dropFirst().allSatisfy { $0 == results[0] })
    }

    func testSourcePriorityOnlyBreaksATieBetweenEquivalentValues() {
        let contextual = TemporalClaim(
            id: "contextual",
            subject: "location",
            value: "Friday",
            assertedAt: nil,
            effectiveAt: nil,
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-contextual"],
            sourcePriority: .contextual
        )
        let explicit = TemporalClaim(
            id: "explicit",
            subject: "location",
            value: "Friday",
            assertedAt: nil,
            effectiveAt: nil,
            correctsClaimIDs: [],
            evidenceIDs: ["evidence-explicit"],
            sourcePriority: .explicitCorrection
        )

        let result = TemporalOracle().adjudicate([explicit, contextual], subject: "location")

        XCTAssertEqual(result.verdict, .current)
        XCTAssertEqual(result.currentClaimID, "explicit")
        XCTAssertTrue(result.claimResults.allSatisfy { $0.status == .current })
    }

    func testHeroCaseResolvesDinnerAndPreparationWithoutAModel() {
        let dinnerClaims = [
            TemporalClaim(
                id: "earlier-audio",
                subject: "dinner-time",
                value: "Thursday 7:00 PM",
                assertedAt: Date(timeIntervalSince1970: 100),
                effectiveAt: nil,
                correctsClaimIDs: [],
                evidenceIDs: ["audio-earlier"]
            ),
            TemporalClaim(
                id: "corrected-invitation",
                subject: "dinner-time",
                value: "Friday 6:30 PM",
                assertedAt: Date(timeIntervalSince1970: 200),
                effectiveAt: Date(timeIntervalSince1970: 400),
                correctsClaimIDs: ["earlier-audio"],
                evidenceIDs: ["photo-correction"],
                sourcePriority: .explicitCorrection
            ),
            TemporalClaim(
                id: "latest-audio",
                subject: "dinner-time",
                value: "Friday 6:30 PM",
                assertedAt: Date(timeIntervalSince1970: 300),
                effectiveAt: Date(timeIntervalSince1970: 400),
                correctsClaimIDs: [],
                evidenceIDs: ["audio-latest"]
            )
        ]
        let preparation = TemporalClaim(
            id: "cake",
            subject: "preparation",
            value: "Bring a dairy-free cake",
            assertedAt: Date(timeIntervalSince1970: 300),
            effectiveAt: nil,
            correctsClaimIDs: [],
            evidenceIDs: ["audio-latest"]
        )
        let allowed = Set(["audio-earlier", "photo-correction", "audio-latest"])

        let dinner = TemporalOracle().adjudicate(
            dinnerClaims,
            subject: "dinner-time",
            allowedEvidenceIDs: allowed
        )
        let prepare = TemporalOracle().adjudicate(
            [preparation],
            subject: "preparation",
            allowedEvidenceIDs: allowed
        )

        XCTAssertEqual(dinner.verdict, .current)
        XCTAssertEqual(dinner.currentClaimID, "latest-audio")
        XCTAssertEqual(
            dinner.claimResults.first(where: { $0.id == "earlier-audio" })?.status,
            .superseded
        )
        XCTAssertEqual(prepare.verdict, .current)
        XCTAssertEqual(prepare.currentClaimID, "cake")
    }

    private func claim(
        id: String,
        value: String,
        corrects: Set<String> = [],
        evidenceID: String
    ) -> TemporalClaim {
        TemporalClaim(
            id: id,
            subject: "location",
            value: value,
            assertedAt: Date(timeIntervalSince1970: 100),
            effectiveAt: nil,
            correctsClaimIDs: corrects,
            evidenceIDs: [evidenceID]
        )
    }
}

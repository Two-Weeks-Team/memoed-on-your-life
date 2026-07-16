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
            correctsClaimIDs: []
        )
        let correction = TemporalClaim(
            id: "correction",
            subject: "dinner-time",
            value: "Friday 6:30 PM",
            assertedAt: Date(timeIntervalSince1970: 200),
            effectiveAt: nil,
            correctsClaimIDs: ["earlier"]
        )

        let result = TemporalOracle().adjudicate([earlier, correction], subject: "dinner-time")

        XCTAssertEqual(result.verdict, .current)
        XCTAssertEqual(result.currentClaimID, "correction")
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
            correctsClaimIDs: []
        )
        let later = TemporalClaim(
            id: "later",
            subject: "location",
            value: "Park",
            assertedAt: Date(timeIntervalSince1970: 200),
            effectiveAt: nil,
            correctsClaimIDs: []
        )

        let result = TemporalOracle().adjudicate([first, later], subject: "location")

        XCTAssertEqual(result.verdict, .ambiguous)
        XCTAssertNil(result.currentClaimID)
    }

    func testMissingSubjectIsUnknown() {
        let result = TemporalOracle().adjudicate([], subject: "unknown")

        XCTAssertEqual(result.verdict, .unknown)
        XCTAssertNil(result.currentClaimID)
        XCTAssertTrue(result.claimResults.isEmpty)
    }
}

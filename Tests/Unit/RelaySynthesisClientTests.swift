import Foundation
import XCTest
@testable import MemoedOnYourLife

final class RelaySynthesisClientTests: XCTestCase {
    func testClientSendsNoAPIKeyAndAcceptsEvidenceBoundCloudResult() async throws {
        let transport = FixtureRelayTransport(.response(status: 200, data: responseData()))
        let client = try RelaySynthesisClient(
            relayBaseURL: try XCTUnwrap(URL(string: "https://relay.example")),
            installationID: "fixture_installation_001",
            flowID: "flow_fixture_001",
            transport: transport
        )

        let answer = try await client.synthesize(
            question: "When is dinner?",
            packet: packet(),
            mode: .standard,
            priorJudgment: nil
        )

        XCTAssertEqual(answer.origin, .cloud)
        XCTAssertEqual(answer.verdict, .current)
        XCTAssertEqual(answer.claims.first?.evidenceIDs, ["photo-correction"])
        XCTAssertEqual(answer.missingEvidence, [])
        XCTAssertEqual(answer.challengeDisposition, .notRun)
        let request = await transport.lastRequest
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request?.value(forHTTPHeaderField: "X-Memoed-Installation"), "fixture_installation_001")
        let body = try XCTUnwrap(request?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "gpt-5.4-mini")
        XCTAssertNil(object["apiKey"])
    }

    func testClientMapsRelayFailureFixturesWithoutAcceptingUserFacts() async throws {
        let fixtures: [(Int, Data, RelayClientError)] = [
            (400, errorData("invalid_schema"), .invalidResponse),
            (401, errorData("installation_required"), .unauthorized),
            (429, errorData("rate_limit"), .rateLimited),
            (500, errorData("provider_unavailable"), .upstreamUnavailable),
            (503, errorData("live_api_disabled"), .liveAPIDisabled)
        ]

        for fixture in fixtures {
            let transport = FixtureRelayTransport(.response(status: fixture.0, data: fixture.1))
            let client = try makeClient(transport: transport)
            do {
                _ = try await client.synthesize(
                    question: "When is dinner?",
                    packet: packet(),
                    mode: .standard,
                    priorJudgment: nil
                )
                XCTFail("HTTP \(fixture.0) must not become a user fact.")
            } catch let error as RelayClientError {
                XCTAssertEqual(error, fixture.2)
            }
        }
    }

    func testClientRejectsTimeoutAndTruncatedJSON() async throws {
        let timeout = FixtureRelayTransport(.failure(.timedOut))
        do {
            _ = try await makeClient(transport: timeout).synthesize(
                question: "When is dinner?",
                packet: packet(),
                mode: .standard,
                priorJudgment: nil
            )
            XCTFail("Timeout must fail closed.")
        } catch let error as RelayClientError {
            XCTAssertEqual(error, .transport)
        }

        let truncated = FixtureRelayTransport(.response(status: 200, data: Data("{\"verdict\":".utf8)))
        do {
            _ = try await makeClient(transport: truncated).synthesize(
                question: "When is dinner?",
                packet: packet(),
                mode: .standard,
                priorJudgment: nil
            )
            XCTFail("Truncated JSON must fail closed.")
        } catch let error as RelayClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testClientRejectsOutOfPacketCitationAndUnexpectedFields() async throws {
        let invalidCitation = responseData(evidenceIDs: ["invented-evidence"])
        let extraField = responseData(extraRootField: true)
        for data in [invalidCitation, extraField] {
            let transport = FixtureRelayTransport(.response(status: 200, data: data))
            do {
                _ = try await makeClient(transport: transport).synthesize(
                    question: "When is dinner?",
                    packet: packet(),
                    mode: .standard,
                    priorJudgment: nil
                )
                XCTFail("Invalid relay output must fail closed.")
            } catch let error as RelayClientError {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testClientRejectsOversizedRequestAndResponse() async throws {
        let transport = FixtureRelayTransport(.response(status: 200, data: responseData()))
        do {
            _ = try await makeClient(transport: transport).synthesize(
                question: String(repeating: "q", count: 1_001),
                packet: packet(),
                mode: .standard,
                priorJudgment: nil
            )
            XCTFail("An oversized question must be rejected before transport.")
        } catch let error as RelayClientError {
            XCTAssertEqual(error, .invalidRequest)
        }
        let dispatchedRequest = await transport.lastRequest
        XCTAssertNil(dispatchedRequest)

        let oversized = FixtureRelayTransport(
            .response(status: 200, data: Data(repeating: 0, count: 128 * 1_024 + 1))
        )
        do {
            _ = try await makeClient(transport: oversized).synthesize(
                question: "When is dinner?",
                packet: packet(),
                mode: .standard,
                priorJudgment: nil
            )
            XCTFail("An oversized relay response must fail closed.")
        } catch let error as RelayClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testClientRejectsInvalidInstallationIdentifier() {
        XCTAssertThrowsError(
            try RelaySynthesisClient(
                relayBaseURL: XCTUnwrap(URL(string: "https://relay.example")),
                installationID: "contains spaces 001",
                flowID: "flow_fixture_001",
                transport: FixtureRelayTransport(.failure(.badURL))
            )
        )
    }

    func testClientDeletesOnlyItsOpaqueInstallationIdentityWithoutAProviderCredential() async throws {
        let transport = FixtureRelayTransport(.response(status: 204, data: Data()))
        let client = try makeClient(transport: transport)

        try await client.deleteInstallationIdentity()

        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/installations/current")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Memoed-Installation"),
            "fixture_installation_001"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
    }

    func testClientFailsClosedWhenInstallationDeletionIsNotConfirmed() async throws {
        let transport = FixtureRelayTransport(.response(status: 200, data: Data("{}".utf8)))
        do {
            try await makeClient(transport: transport).deleteInstallationIdentity()
            XCTFail("Only an empty 204 response confirms deletion.")
        } catch let error as RelayClientError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testChallengeRequiresStructuredPriorJudgment() throws {
        XCTAssertThrowsError(
            try RelaySynthesisRequest(
                flowID: "flow_fixture_001",
                question: "Challenge it",
                packet: packet(purpose: .challenge),
                mode: .challenge,
                priorJudgment: nil
            )
        )
    }

    func testOnDeviceFallbackIsExplicitlyLabeled() async throws {
        let answer = try await OnDeviceAnswerSynthesisService().synthesize(
            question: "When is dinner?",
            evidence: packet().items.map(\.evidence),
            mode: .standard
        )
        XCTAssertEqual(answer.origin, .onDevice)
        XCTAssertEqual(answer.origin.localizationKey, "synthesis.origin.on_device")
        XCTAssertEqual(answer.challengeDisposition, .notRun)
        XCTAssertFalse(answer.claims.isEmpty)
    }

    private func makeClient(transport: any RelayHTTPTransport) throws -> RelaySynthesisClient {
        try RelaySynthesisClient(
            relayBaseURL: XCTUnwrap(URL(string: "https://relay.example")),
            installationID: "fixture_installation_001",
            flowID: "flow_fixture_001",
            transport: transport
        )
    }

    private func packet(purpose: RetrievalPurpose = .defaultAnswer) -> EvidencePacket {
        let evidence = EvidenceSnippet(
            id: "photo-correction",
            sourceKind: .imageOCRCrop,
            excerpt: "Corrected invitation: Friday at 6:30 PM.",
            capturedAt: Date(timeIntervalSince1970: 100),
            assertedAt: Date(timeIntervalSince1970: 90),
            coordinate: .normalizedCrop(x: 0.08, y: 0.18, width: 0.84, height: 0.22)
        )
        return EvidencePacket(
            purpose: purpose,
            queryTerms: ["dinner"],
            items: [RankedEvidence(evidence: evidence, score: 10, matchedTerms: ["dinner"])],
            consumedCharacters: evidence.excerpt.count
        )
    }

    private func responseData(
        evidenceIDs: [String] = ["photo-correction"],
        extraRootField: Bool = false
    ) -> Data {
        var object: [String: Any] = [
            "schemaVersion": "memoed.relay.response.v1",
            "source": "cloud",
            "model": "gpt-5.4-mini",
            "verdict": "current",
            "answer": "Dinner is Friday at 6:30 PM.",
            "claims": [[
                "id": "dinner-time",
                "text": "Dinner is Friday at 6:30 PM.",
                "status": "current",
                "confidence": "high",
                "evidenceIDs": evidenceIDs
            ]],
            "why": "The invitation explicitly corrects the earlier plan.",
            "missingEvidence": [],
            "challengeDisposition": "not_run"
        ]
        if extraRootField { object["unexpected"] = true }
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func errorData(_ code: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": ["code": code]])
    }
}

private actor FixtureRelayTransport: RelayHTTPTransport {
    enum Outcome: Sendable {
        case response(status: Int, data: Data)
        case failure(URLError.Code)
    }

    private let outcome: Outcome
    private(set) var lastRequest: URLRequest?

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func send(_ request: URLRequest) async throws -> RelayHTTPResponse {
        lastRequest = request
        switch outcome {
        case let .response(status, data):
            return RelayHTTPResponse(data: data, statusCode: status)
        case let .failure(code):
            throw URLError(code)
        }
    }
}

import Foundation

private let relayRequestSchemaVersion = "memoed.relay.request.v1"
private let relayResponseSchemaVersion = "memoed.relay.response.v1"
private let relayAllowedModel = "gpt-5.4-mini"
private let relayMaximumRequestBytes = 64 * 1_024
private let relayMaximumResponseBytes = 128 * 1_024

enum RelaySynthesisPurpose: String, Codable, Sendable {
    case `default`
    case challenge
}

struct RelayCoordinate: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case audioInterval = "audio_interval"
        case normalizedCrop = "normalized_crop"
    }

    let kind: Kind
    let startMilliseconds: Int?
    let endMilliseconds: Int?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
}

struct RelayEvidenceItem: Codable, Equatable, Sendable {
    enum SourceKind: String, Codable, Sendable {
        case audioTranscriptSpan = "audio_transcript_span"
        case imageOCRCrop = "image_ocr_crop"
    }

    let id: String
    let sourceKind: SourceKind
    let excerpt: String
    let capturedAt: Date
    let assertedAt: Date?
    let coordinate: RelayCoordinate
}

struct RelayPriorJudgment: Codable, Equatable, Sendable {
    struct Claim: Codable, Equatable, Sendable {
        let id: String
        let text: String
        let status: EvidenceVerdict
        let evidenceIDs: [String]
    }

    let verdict: EvidenceVerdict
    let claims: [Claim]

    init(_ answer: SynthesizedAnswer) {
        verdict = answer.verdict
        claims = answer.claims.map {
            Claim(id: $0.id, text: $0.text, status: $0.verdict, evidenceIDs: $0.evidenceIDs)
        }
    }
}

struct RelaySynthesisRequest: Codable, Equatable, Sendable {
    struct Packet: Codable, Equatable, Sendable {
        let purpose: RelaySynthesisPurpose
        let items: [RelayEvidenceItem]
    }

    let schemaVersion: String
    let flowID: String
    let model: String
    let purpose: RelaySynthesisPurpose
    let question: String
    let maxOutputTokens: Int
    let structuredClaim: RelayPriorJudgment?
    let evidencePacket: Packet

    init(
        flowID: String,
        question: String,
        packet: EvidencePacket,
        mode: AnswerSynthesisMode,
        priorJudgment: SynthesizedAnswer?
    ) throws {
        let purpose: RelaySynthesisPurpose = mode == .challenge ? .challenge : .default
        guard (purpose == .challenge) == (priorJudgment != nil) else {
            throw RelayClientError.invalidRequest
        }
        guard (1 ... 1_000).contains(question.count),
              (1 ... 12).contains(packet.items.count),
              packet.allowedEvidenceIDs.count == packet.items.count,
              packet.items.allSatisfy({ item in
                  Self.validID(item.id)
                      && (1 ... 2_000).contains(item.evidence.excerpt.count)
              }),
              packet.items.reduce(0, { $0 + $1.evidence.excerpt.utf8.count }) <= 6_000,
              (mode == .standard) == (packet.purpose == .defaultAnswer),
              Self.validPriorJudgment(priorJudgment) else {
            throw RelayClientError.invalidRequest
        }
        schemaVersion = relayRequestSchemaVersion
        self.flowID = flowID
        model = relayAllowedModel
        self.purpose = purpose
        self.question = question
        maxOutputTokens = 2_000
        structuredClaim = priorJudgment.map(RelayPriorJudgment.init)
        evidencePacket = Packet(
            purpose: purpose,
            items: try packet.items.map(Self.makeEvidenceItem)
        )
    }

    private static func makeEvidenceItem(_ item: RankedEvidence) throws -> RelayEvidenceItem {
        let coordinate: RelayCoordinate
        let sourceKind: RelayEvidenceItem.SourceKind
        switch item.evidence.coordinate {
        case let .audioInterval(start, end):
            guard end > start else { throw RelayClientError.invalidRequest }
            sourceKind = .audioTranscriptSpan
            coordinate = RelayCoordinate(
                kind: .audioInterval,
                startMilliseconds: start,
                endMilliseconds: end,
                x: nil,
                y: nil,
                width: nil,
                height: nil
            )
        case let .normalizedCrop(x, y, width, height):
            guard x >= 0, y >= 0, width > 0, height > 0,
                  x + width <= 1.000_001, y + height <= 1.000_001 else {
                throw RelayClientError.invalidRequest
            }
            sourceKind = .imageOCRCrop
            coordinate = RelayCoordinate(
                kind: .normalizedCrop,
                startMilliseconds: nil,
                endMilliseconds: nil,
                x: x,
                y: y,
                width: width,
                height: height
            )
        }
        return RelayEvidenceItem(
            id: item.id,
            sourceKind: sourceKind,
            excerpt: item.evidence.excerpt,
            capturedAt: item.evidence.capturedAt,
            assertedAt: item.evidence.assertedAt,
            coordinate: coordinate
        )
    }

    private static func validID(_ value: String) -> Bool {
        (1 ... 128).contains(value.count)
            && value.range(
                of: "^[A-Za-z0-9][A-Za-z0-9:_-]*$",
                options: .regularExpression
            ) != nil
    }

    private static func validPriorJudgment(_ answer: SynthesizedAnswer?) -> Bool {
        guard let answer else { return true }
        return (1 ... 12).contains(answer.claims.count)
            && Set(answer.claims.map(\.id)).count == answer.claims.count
            && answer.claims.allSatisfy { claim in
                validID(claim.id)
                    && (1 ... 1_000).contains(claim.text.count)
                    && claim.evidenceIDs.count <= 12
                    && Set(claim.evidenceIDs).count == claim.evidenceIDs.count
                    && claim.evidenceIDs.allSatisfy(validID)
            }
    }
}

private struct RelaySynthesisResponse: Codable, Sendable {
    struct Claim: Codable, Sendable {
        let id: String
        let text: String
        let status: EvidenceVerdict
        let confidence: String
        let evidenceIDs: [String]
    }

    let schemaVersion: String
    let source: String
    let model: String
    let verdict: EvidenceVerdict
    let answer: String
    let claims: [Claim]
    let why: String
    let missingEvidence: [String]
    let challengeDisposition: ChallengeDisposition
}

struct RelayHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

protocol RelayHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> RelayHTTPResponse
}

actor URLSessionRelayHTTPTransport: RelayHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> RelayHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RelayClientError.invalidResponse
        }
        return RelayHTTPResponse(data: data, statusCode: http.statusCode)
    }
}

enum RelayClientError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case unauthorized
    case rateLimited
    case liveAPIDisabled
    case upstreamUnavailable
    case transport
}

protocol RelaySynthesisProviding: Sendable {
    func synthesize(
        question: String,
        packet: EvidencePacket,
        mode: AnswerSynthesisMode,
        priorJudgment: SynthesizedAnswer?
    ) async throws -> SynthesizedAnswer
}

struct RelaySynthesisClient: RelaySynthesisProviding, Sendable {
    private let endpoint: URL
    private let installationID: String
    private let flowID: String
    private let transport: any RelayHTTPTransport

    init(
        relayBaseURL: URL,
        installationID: String,
        flowID: String,
        transport: any RelayHTTPTransport = URLSessionRelayHTTPTransport()
    ) throws {
        guard (16 ... 128).contains(installationID.count),
              installationID.range(
                  of: "^[A-Za-z0-9_-]+$",
                  options: .regularExpression
              ) != nil,
              (1 ... 128).contains(flowID.count),
              flowID.range(
                  of: "^[A-Za-z0-9][A-Za-z0-9:_-]*$",
                  options: .regularExpression
              ) != nil else {
            throw RelayClientError.invalidRequest
        }
        endpoint = relayBaseURL.appendingPathComponent("v1/synthesize")
        self.installationID = installationID
        self.flowID = flowID
        self.transport = transport
    }

    func synthesize(
        question: String,
        packet: EvidencePacket,
        mode: AnswerSynthesisMode,
        priorJudgment: SynthesizedAnswer?
    ) async throws -> SynthesizedAnswer {
        let body = try RelaySynthesisRequest(
            flowID: flowID,
            question: question,
            packet: packet,
            mode: mode,
            priorJudgment: priorJudgment
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installationID, forHTTPHeaderField: "X-Memoed-Installation")
        request.httpBody = try encoder.encode(body)
        guard request.httpBody?.count ?? 0 <= relayMaximumRequestBytes else {
            throw RelayClientError.invalidRequest
        }

        let response: RelayHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw RelayClientError.transport
        }
        switch response.statusCode {
        case 200:
            guard response.data.count <= relayMaximumResponseBytes else {
                throw RelayClientError.invalidResponse
            }
            return try decode(
                response.data,
                allowedEvidenceIDs: packet.allowedEvidenceIDs,
                mode: mode
            )
        case 401, 403:
            throw RelayClientError.unauthorized
        case 429:
            throw RelayClientError.rateLimited
        case 503:
            if let code = try? errorCode(from: response.data), code == "live_api_disabled" {
                throw RelayClientError.liveAPIDisabled
            }
            throw RelayClientError.upstreamUnavailable
        case 500 ... 599:
            throw RelayClientError.upstreamUnavailable
        default:
            throw RelayClientError.invalidResponse
        }
    }

    private func decode(
        _ data: Data,
        allowedEvidenceIDs: Set<String>,
        mode: AnswerSynthesisMode
    ) throws -> SynthesizedAnswer {
        guard hasExactResponseShape(data) else {
            throw RelayClientError.invalidResponse
        }
        let response: RelaySynthesisResponse
        do {
            response = try JSONDecoder().decode(RelaySynthesisResponse.self, from: data)
        } catch {
            throw RelayClientError.invalidResponse
        }
        guard response.schemaVersion == relayResponseSchemaVersion,
              response.source == "cloud",
              response.model == relayAllowedModel,
              !response.answer.isEmpty,
              response.answer.count <= 1_000,
              !response.why.isEmpty,
              response.why.count <= 2_000,
              response.claims.count <= 12,
              response.missingEvidence.count <= 8,
              Set(response.missingEvidence).count == response.missingEvidence.count,
              response.missingEvidence.allSatisfy({ (1 ... 300).contains($0.count) }),
              Set(response.claims.map(\.id)).count == response.claims.count,
              response.claims.allSatisfy({ claim in
                  (1 ... 128).contains(claim.id.count)
                      && claim.id.range(
                          of: "^[A-Za-z0-9][A-Za-z0-9:_-]*$",
                          options: .regularExpression
                      ) != nil
                      && (1 ... 1_000).contains(claim.text.count)
                      && claim.evidenceIDs.count <= 12
                      && Set(claim.evidenceIDs).count == claim.evidenceIDs.count
                      && Set(claim.evidenceIDs).isSubset(of: allowedEvidenceIDs)
                      && (claim.status == .unknown || !claim.evidenceIDs.isEmpty)
              }) else {
            throw RelayClientError.invalidResponse
        }
        let allowedConfidence = Set(["low", "medium", "high"])
        guard response.claims.allSatisfy({ allowedConfidence.contains($0.confidence) }) else {
            throw RelayClientError.invalidResponse
        }
        guard (mode == .standard) == (response.challengeDisposition == .notRun) else {
            throw RelayClientError.invalidResponse
        }
        return SynthesizedAnswer(
            verdict: response.verdict,
            answer: response.answer,
            claims: response.claims.map {
                SynthesizedClaim(
                    id: $0.id,
                    text: $0.text,
                    verdict: $0.status,
                    evidenceIDs: $0.evidenceIDs
                )
            },
            why: response.why,
            missingEvidence: response.missingEvidence,
            challengeDisposition: response.challengeDisposition,
            origin: .cloud
        )
    }

    private func hasExactResponseShape(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let expectedRoot = Set([
            "schemaVersion", "source", "model", "verdict", "answer", "claims", "why",
            "missingEvidence", "challengeDisposition"
        ])
        guard Set(root.keys) == expectedRoot,
              let claims = root["claims"] as? [[String: Any]] else {
            return false
        }
        let expectedClaim = Set(["id", "text", "status", "confidence", "evidenceIDs"])
        return claims.allSatisfy { Set($0.keys) == expectedClaim }
    }

    private func errorCode(from data: Data) throws -> String {
        struct Envelope: Decodable {
            struct ErrorBody: Decodable { let code: String }
            let error: ErrorBody
        }
        return try JSONDecoder().decode(Envelope.self, from: data).error.code
    }
}

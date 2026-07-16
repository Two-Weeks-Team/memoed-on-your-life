import XCTest
import UIKit
@testable import MemoedOnYourLife

@MainActor
final class CapturedEvidenceTests: XCTestCase {
    func testNormalizedCropClampsToUnitSpace() {
        let crop = NormalizedCrop(x: -0.2, y: 0.8, width: 1.4, height: 0.6)

        XCTAssertEqual(crop.x, 0)
        XCTAssertEqual(crop.y, 0.8)
        XCTAssertEqual(crop.width, 1)
        XCTAssertEqual(crop.height, 0.2, accuracy: 0.000_001)
    }

    func testStoreRoundTripPreservesProtectedManifestData() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalEvidenceStore(rootURL: root)
        let imported = try await store.importData(
            Data("photo-bytes".utf8),
            kind: .photo,
            fileExtension: "jpg",
            originalFilename: "source.jpg",
            mediaTypeIdentifier: "public.jpeg"
        )

        var updated = imported
        updated.state = .ready
        updated.ocrBlocks = [Self.block]
        try await store.update(updated)

        let reloadedStore = LocalEvidenceStore(rootURL: root)
        let reloaded = try await reloadedStore.loadAssets()
        let reloadedData = try await reloadedStore.data(for: updated)
        let restored = try XCTUnwrap(reloaded.first)

        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(restored.id, updated.id)
        XCTAssertEqual(restored.kind, updated.kind)
        XCTAssertEqual(restored.state, updated.state)
        XCTAssertEqual(restored.ocrBlocks, updated.ocrBlocks)
        XCTAssertEqual(
            restored.capturedAt.timeIntervalSince1970,
            updated.capturedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(reloadedData, Data("photo-bytes".utf8))
    }

    func testIndexerReplacesResultsInsteadOfDuplicatingThem() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalEvidenceStore(rootURL: root)
        let imported = try await store.importData(
            Data("fixture".utf8),
            kind: .photo,
            fileExtension: "png",
            originalFilename: "fixture.png",
            mediaTypeIdentifier: "public.png"
        )
        let indexer = EvidenceIndexer(
            store: store,
            photoRecognizer: StubPhotoRecognizer(blocks: [Self.block]),
            audioTranscriber: StubAudioTranscriber()
        )

        _ = await indexer.index(assetID: imported.id, localeIdentifier: "en-US")
        let second = await indexer.index(assetID: imported.id, localeIdentifier: "en-US")

        XCTAssertEqual(second?.state, .ready)
        XCTAssertEqual(second?.ocrBlocks, [Self.block])
    }

    func testStoreRoundTripPreservesTimedTranscriptAndSourceAudio() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalEvidenceStore(rootURL: root)
        let sourceData = Data("audio-fixture".utf8)
        let imported = try await store.importData(
            sourceData,
            kind: .audio,
            fileExtension: "m4a",
            originalFilename: "fixture.m4a",
            mediaTypeIdentifier: "public.mpeg-4-audio"
        )

        var updated = imported
        updated.state = .ready
        updated.transcriptSpans = [Self.transcriptSpan]
        try await store.update(updated)

        let reloadedStore = LocalEvidenceStore(rootURL: root)
        let restoredValue = try await reloadedStore.evidence(id: imported.id)
        let restored = try XCTUnwrap(restoredValue)
        let restoredData = try await reloadedStore.data(for: restored)

        XCTAssertEqual(restored.transcriptSpans, [Self.transcriptSpan])
        XCTAssertEqual(restoredData, sourceData)
    }

    func testAppleVisionReadsSyntheticInvitationWithNormalizedRegions() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            NSString(string: "FRIDAY 6:30 PM").draw(
                at: CGPoint(x: 70, y: 95),
                withAttributes: attributes
            )
        }
        let data = try XCTUnwrap(image.pngData())

        let blocks = try await AppleVisionTextRecognizer().recognizeText(in: data)
        let recognized = blocks.map(\.text).joined(separator: " ").uppercased()

        XCTAssertTrue(recognized.contains("FRIDAY"), recognized)
        XCTAssertTrue(blocks.allSatisfy {
            $0.crop.x >= 0 && $0.crop.y >= 0
                && $0.crop.x + $0.crop.width <= 1
                && $0.crop.y + $0.crop.height <= 1
        })
    }

    func testIndexerRejectsAnEmptyAudioTranscript() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalEvidenceStore(rootURL: root)
        let imported = try await store.importData(
            Data("silent-audio".utf8),
            kind: .audio,
            fileExtension: "m4a",
            originalFilename: "silent.m4a",
            mediaTypeIdentifier: "public.mpeg-4-audio"
        )
        let indexer = EvidenceIndexer(
            store: store,
            photoRecognizer: StubPhotoRecognizer(blocks: []),
            audioTranscriber: StubAudioTranscriber()
        )

        let result = await indexer.index(
            assetID: imported.id,
            localeIdentifier: "en-US"
        )

        XCTAssertEqual(result?.state, .failed)
        XCTAssertEqual(result?.failureCode, .unreadableMedia)
        XCTAssertTrue(result?.transcriptSpans.isEmpty == true)
    }

    func testIndexerPreservesUnsupportedAndUnavailableSpeechFailures() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalEvidenceStore(rootURL: root)
        let unsupported = try await store.importData(
            Data("unsupported".utf8),
            kind: .audio,
            fileExtension: "m4a",
            originalFilename: "unsupported.m4a",
            mediaTypeIdentifier: "public.mpeg-4-audio"
        )
        let unavailable = try await store.importData(
            Data("unavailable".utf8),
            kind: .audio,
            fileExtension: "m4a",
            originalFilename: "unavailable.m4a",
            mediaTypeIdentifier: "public.mpeg-4-audio"
        )

        let unsupportedIndexer = EvidenceIndexer(
            store: store,
            photoRecognizer: StubPhotoRecognizer(blocks: []),
            audioTranscriber: FailingAudioTranscriber(error: .unsupportedLanguage)
        )
        let unavailableIndexer = EvidenceIndexer(
            store: store,
            photoRecognizer: StubPhotoRecognizer(blocks: []),
            audioTranscriber: FailingAudioTranscriber(error: .assetsUnavailable)
        )

        let unsupportedResult = await unsupportedIndexer.index(
            assetID: unsupported.id,
            localeIdentifier: "zz-ZZ"
        )
        let unavailableResult = await unavailableIndexer.index(
            assetID: unavailable.id,
            localeIdentifier: "en-US"
        )

        XCTAssertEqual(unsupportedResult?.state, .failed)
        XCTAssertEqual(unsupportedResult?.failureCode, .unsupportedLanguage)
        XCTAssertEqual(unavailableResult?.state, .failed)
        XCTAssertEqual(unavailableResult?.failureCode, .speechAssetsUnavailable)
    }

    func testMicrophonePermissionDenialBecomesVisibleOperationFailure() async {
        let model = EvidenceLibraryModel(recorder: DeniedAudioCapture())

        await model.toggleRecording()

        XCTAssertEqual(model.operation, .failed(.microphonePermissionDenied))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "memoed-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static let block = OCRTextBlock(
        id: UUID(uuidString: "43C45ED8-66E2-4FE5-8849-E79C6A86A406")!,
        text: "Friday 6:30 PM",
        confidence: 0.98,
        crop: NormalizedCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.2),
        languageIdentifiers: ["en"]
    )

    private static let transcriptSpan = AudioTranscriptSpan(
        id: UUID(uuidString: "2F6CF780-5F79-4B06-9B84-D0F2EBC1A2DB")!,
        text: "Friday at 6:30 PM",
        startMilliseconds: 1_250,
        endMilliseconds: 2_800
    )
}

private struct StubPhotoRecognizer: PhotoTextRecognizing {
    let blocks: [OCRTextBlock]

    func recognizeText(in data: Data) async throws -> [OCRTextBlock] {
        blocks
    }
}

private struct StubAudioTranscriber: AudioTranscribing {
    func transcribe(
        fileURL: URL,
        localeIdentifier: String
    ) async throws -> [AudioTranscriptSpan] {
        []
    }
}

private struct FailingAudioTranscriber: AudioTranscribing {
    let error: SpeechPerceptionError

    func transcribe(
        fileURL: URL,
        localeIdentifier: String
    ) async throws -> [AudioTranscriptSpan] {
        throw error
    }
}

@MainActor
private final class DeniedAudioCapture: AudioCapturing {
    var isRecording: Bool { false }

    func start() async throws {
        throw AudioCaptureError.permissionDenied
    }

    func stop() throws -> RecordedAudio {
        throw AudioCaptureError.unavailable
    }
}

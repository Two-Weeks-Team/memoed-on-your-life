import Foundation
import Observation

@MainActor
@Observable
final class EvidenceLibraryModel {
    enum Operation: Equatable {
        case idle
        case importingPhoto
        case recording
        case savingAudio
        case indexing(CapturedEvidenceKind)
        case complete
        case failed(EvidenceFailureCode)
    }

    private let store: LocalEvidenceStore
    private let indexer: EvidenceIndexer
    private let recorder: any AudioCapturing

    var assets: [CapturedEvidence] = []
    var operation: Operation = .idle

    var isRecording: Bool {
        recorder.isRecording
    }

    init(
        store: LocalEvidenceStore = LocalEvidenceStore(),
        photoRecognizer: any PhotoTextRecognizing = AppleVisionTextRecognizer(),
        audioTranscriber: any AudioTranscribing = AppleSpeechFileTranscriber(),
        recorder: any AudioCapturing = AudioCaptureController()
    ) {
        self.store = store
        self.indexer = EvidenceIndexer(
            store: store,
            photoRecognizer: photoRecognizer,
            audioTranscriber: audioTranscriber
        )
        self.recorder = recorder
    }

    func load() async {
        do {
            assets = try await store.loadAssets()
        } catch {
            operation = .failed(.processingFailed)
        }
    }

    func importPhoto(
        data: Data,
        fileExtension: String,
        originalFilename: String,
        mediaTypeIdentifier: String
    ) async {
        operation = .importingPhoto
        do {
            let asset = try await store.importData(
                data,
                kind: .photo,
                fileExtension: fileExtension,
                originalFilename: originalFilename,
                mediaTypeIdentifier: mediaTypeIdentifier
            )
            try await refreshAssets()
            operation = .indexing(.photo)
            let result = await indexer.index(
                assetID: asset.id,
                localeIdentifier: Locale.current.identifier
            )
            try await refreshAssets()
            operation = result?.state == .ready
                ? .complete
                : .failed(result?.failureCode ?? .processingFailed)
        } catch {
            operation = .failed(.photoUnavailable)
        }
    }

    func reportPhotoLoadFailure() {
        operation = .failed(.photoUnavailable)
    }

    func toggleRecording() async {
        if recorder.isRecording {
            await stopAndIndexRecording()
        } else {
            await startRecording()
        }
    }

    func retry(_ asset: CapturedEvidence) async {
        operation = .indexing(asset.kind)
        let result = await indexer.index(
            assetID: asset.id,
            localeIdentifier: Locale.current.identifier
        )
        try? await refreshAssets()
        operation = result?.state == .ready
            ? .complete
            : .failed(result?.failureCode ?? .processingFailed)
    }

    func delete(_ asset: CapturedEvidence) async {
        do {
            try await store.delete(asset)
            try await refreshAssets()
        } catch {
            operation = .failed(.processingFailed)
        }
    }

    func data(for asset: CapturedEvidence) async -> Data? {
        try? await store.data(for: asset)
    }

    func clearStatus() {
        guard operation != .recording else { return }
        operation = .idle
    }

    private func startRecording() async {
        do {
            try await recorder.start()
            operation = .recording
        } catch AudioCaptureError.permissionDenied {
            operation = .failed(.microphonePermissionDenied)
        } catch {
            operation = .failed(.microphoneUnavailable)
        }
    }

    private func stopAndIndexRecording() async {
        operation = .savingAudio
        do {
            let recorded = try recorder.stop()
            defer { try? FileManager.default.removeItem(at: recorded.temporaryURL) }
            guard recorded.duration > 0.2 else {
                operation = .failed(.unreadableMedia)
                return
            }
            let asset = try await store.importFile(
                at: recorded.temporaryURL,
                kind: .audio,
                originalFilename: "Recording.m4a",
                mediaTypeIdentifier: "public.mpeg-4-audio"
            )
            try await refreshAssets()
            operation = .indexing(.audio)
            let result = await indexer.index(
                assetID: asset.id,
                localeIdentifier: Locale.current.identifier
            )
            try await refreshAssets()
            operation = result?.state == .ready
                ? .complete
                : .failed(result?.failureCode ?? .processingFailed)
        } catch AudioCaptureError.permissionDenied {
            operation = .failed(.microphonePermissionDenied)
        } catch {
            operation = .failed(.processingFailed)
        }
    }

    private func refreshAssets() async throws {
        assets = try await store.loadAssets()
    }
}

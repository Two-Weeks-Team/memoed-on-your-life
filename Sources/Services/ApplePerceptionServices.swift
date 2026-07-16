import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import Speech
import Vision

protocol PhotoTextRecognizing: Sendable {
    func recognizeText(in data: Data) async throws -> [OCRTextBlock]
}

protocol AudioTranscribing: Sendable {
    func transcribe(fileURL: URL, localeIdentifier: String) async throws -> [AudioTranscriptSpan]
}

enum SpeechPerceptionError: Error, Equatable {
    case unavailable
    case unsupportedLanguage
    case assetsUnavailable
    case invalidAudio
}

struct AppleVisionTextRecognizer: PhotoTextRecognizing {
    func recognizeText(in data: Data) async throws -> [OCRTextBlock] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.minimumTextHeightFraction = 0.012

        let observations = try await request.perform(
            on: data,
            orientation: Self.orientation(in: data)
        )
        return observations.compactMap { observation in
            let text = observation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let xs = [
                observation.topLeft.x,
                observation.topRight.x,
                observation.bottomLeft.x,
                observation.bottomRight.x
            ]
            let ys = [
                observation.topLeft.y,
                observation.topRight.y,
                observation.bottomLeft.y,
                observation.bottomRight.y
            ]
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 0
            return OCRTextBlock(
                id: observation.uuid,
                text: text,
                confidence: observation.confidence,
                crop: NormalizedCrop(
                    x: Double(minX),
                    y: Double(minY),
                    width: Double(maxX - minX),
                    height: Double(maxY - minY)
                ),
                languageIdentifiers: observation.recognitionLanguages.map(\.minimalIdentifier)
            )
        }
    }

    private static func orientation(in data: Data) -> CGImagePropertyOrientation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawValue = properties[kCGImagePropertyOrientation] as? UInt32 else {
            return nil
        }
        return CGImagePropertyOrientation(rawValue: rawValue)
    }
}

struct AppleSpeechFileTranscriber: AudioTranscribing {
    func transcribe(fileURL: URL, localeIdentifier: String) async throws -> [AudioTranscriptSpan] {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechPerceptionError.unavailable
        }
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        ) else {
            throw SpeechPerceptionError.unsupportedLanguage
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        guard status != .unsupported else {
            throw SpeechPerceptionError.unsupportedLanguage
        }

        do {
            if let installation = try await AssetInventory.assetInstallationRequest(
                supporting: modules
            ) {
                try await installation.downloadAndInstall()
            }
        } catch {
            throw SpeechPerceptionError.assetsUnavailable
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw SpeechPerceptionError.invalidAudio
        }

        let analyzer = SpeechAnalyzer(modules: modules)
        async let spans = Self.collectFinalSpans(from: transcriber)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let finalizedSpans = try await spans
        guard !finalizedSpans.isEmpty else {
            throw SpeechPerceptionError.invalidAudio
        }
        return finalizedSpans
    }

    private static func collectFinalSpans(
        from transcriber: SpeechTranscriber
    ) async throws -> [AudioTranscriptSpan] {
        var spans: [AudioTranscriptSpan] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let startSeconds = max(CMTimeGetSeconds(result.range.start), 0)
            let durationSeconds = max(CMTimeGetSeconds(result.range.duration), 0)
            let start = Int((startSeconds * 1_000).rounded())
            let end = Int(((startSeconds + durationSeconds) * 1_000).rounded())
            spans.append(AudioTranscriptSpan(
                id: UUID(),
                text: text,
                startMilliseconds: start,
                endMilliseconds: max(end, start)
            ))
        }
        return spans
    }
}

actor EvidenceIndexer {
    private let store: LocalEvidenceStore
    private let photoRecognizer: any PhotoTextRecognizing
    private let audioTranscriber: any AudioTranscribing

    init(
        store: LocalEvidenceStore,
        photoRecognizer: any PhotoTextRecognizing,
        audioTranscriber: any AudioTranscribing
    ) {
        self.store = store
        self.photoRecognizer = photoRecognizer
        self.audioTranscriber = audioTranscriber
    }

    func index(assetID: UUID, localeIdentifier: String) async -> CapturedEvidence? {
        guard var asset = try? await store.evidence(id: assetID) else { return nil }
        asset.state = .indexing
        asset.failureCode = nil
        try? await store.update(asset)

        do {
            switch asset.kind {
            case .photo:
                let data = try await store.data(for: asset)
                asset.ocrBlocks = try await photoRecognizer.recognizeText(in: data)
                asset.transcriptSpans = []
            case .audio:
                let url = await store.assetURL(for: asset)
                let transcriptSpans = try await audioTranscriber.transcribe(
                    fileURL: url,
                    localeIdentifier: localeIdentifier
                )
                guard !transcriptSpans.isEmpty else {
                    throw SpeechPerceptionError.invalidAudio
                }
                asset.transcriptSpans = transcriptSpans
                asset.ocrBlocks = []
            }
            asset.state = .ready
        } catch let error as SpeechPerceptionError {
            asset.state = .failed
            asset.failureCode = switch error {
            case .unsupportedLanguage: .unsupportedLanguage
            case .assetsUnavailable: .speechAssetsUnavailable
            case .invalidAudio: .unreadableMedia
            case .unavailable: .processingFailed
            }
        } catch {
            asset.state = .failed
            asset.failureCode = asset.kind == .photo ? .unreadableMedia : .processingFailed
        }

        try? await store.update(asset)
        return asset
    }
}

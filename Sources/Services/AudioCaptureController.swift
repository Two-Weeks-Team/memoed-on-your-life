import AVFoundation
import Foundation

struct RecordedAudio: Sendable {
    let temporaryURL: URL
    let duration: TimeInterval
}

enum AudioCaptureError: Error, Equatable {
    case permissionDenied
    case unavailable
    case couldNotStart
}

@MainActor
final class AudioCaptureController {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start() async throws {
        guard !isRecording else { return }
        guard await microphonePermissionGranted() else {
            throw AudioCaptureError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioCaptureError.unavailable
        }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "memoed-\(UUID().uuidString).m4a", directoryHint: .notDirectory)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.prepareToRecord(), recorder.record() else {
                throw AudioCaptureError.couldNotStart
            }
            self.recorder = recorder
            self.recordingURL = url
        } catch let error as AudioCaptureError {
            throw error
        } catch {
            throw AudioCaptureError.couldNotStart
        }
    }

    func stop() throws -> RecordedAudio {
        guard let recorder, let recordingURL else {
            throw AudioCaptureError.unavailable
        }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        return RecordedAudio(temporaryURL: recordingURL, duration: duration)
    }

    private func microphonePermissionGranted() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        case .undetermined:
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            false
        }
    }
}

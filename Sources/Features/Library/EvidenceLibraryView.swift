import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct EvidenceLibraryView: View {
    @Bindable var model: EvidenceLibraryModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingDeletion: CapturedEvidence?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: MemoedTheme.contentSpacing) {
                    captureCard
                    operationCard
                    libraryContent
                }
                .padding(.horizontal, MemoedTheme.pagePadding)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("library.title"))
            .task { await model.load() }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await importPhoto(item) }
            }
            .confirmationDialog(
                "library.delete.confirmation.title",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("library.delete", role: .destructive) {
                    guard let asset = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { await model.delete(asset) }
                }
                Button("action.cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("library.delete.confirmation.message")
            }
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("library.capture.title", systemImage: "tray.and.arrow.down.fill")
                .font(.headline)
            Text("library.capture.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("library.photo.action", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .disabled(isBusy)
            .accessibilityIdentifier("import-photo")

            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label(
                    model.isRecording ? "library.audio.stop" : "library.audio.start",
                    systemImage: model.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(model.isRecording ? .red : .indigo)
            .disabled(isBusy && !model.isRecording)
            .accessibilityIdentifier("record-audio")

            Label("library.capture.privacy", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    @ViewBuilder
    private var operationCard: some View {
        if model.operation != .idle {
            HStack(alignment: .top, spacing: 12) {
                operationIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(operationTitle)
                        .font(.headline)
                        .accessibilityIdentifier("library-operation-title")
                    Text(operationDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("library-operation-detail")
                }
                Spacer()
                if canDismissStatus {
                    Button("action.done") { model.clearStatus() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.assets.isEmpty {
            ContentUnavailableView(
                "library.empty.title",
                systemImage: "archivebox",
                description: Text("library.empty.detail")
            )
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("library.saved.title")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(model.assets) { asset in
                    NavigationLink {
                        CapturedEvidenceDetailView(asset: asset, model: model)
                    } label: {
                        EvidenceRow(asset: asset)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("evidence-row-\(asset.kind.rawValue)")
                    .contextMenu {
                        if asset.state == .failed {
                            Button("library.retry", systemImage: "arrow.clockwise") {
                                Task { await model.retry(asset) }
                            }
                        }
                        Button("library.delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = asset
                        }
                    }
                    .accessibilityAction(named: Text("library.delete")) {
                        pendingDeletion = asset
                    }
                }
            }
        }
    }

    private var isBusy: Bool {
        switch model.operation {
        case .importingPhoto, .savingAudio, .indexing:
            true
        default:
            false
        }
    }

    private var canDismissStatus: Bool {
        switch model.operation {
        case .complete, .failed:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private var operationIcon: some View {
        switch model.operation {
        case .complete:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .recording:
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
        default:
            ProgressView().tint(.indigo)
        }
    }

    private var operationTitle: LocalizedStringKey {
        switch model.operation {
        case .idle: "library.status.idle"
        case .importingPhoto: "library.status.importing"
        case .recording: "library.status.recording"
        case .savingAudio: "library.status.saving"
        case .indexing(.photo): "library.status.vision"
        case .indexing(.audio): "library.status.speech"
        case .complete: "library.status.complete"
        case .failed: "library.status.failed"
        }
    }

    private var operationDetail: LocalizedStringKey {
        switch model.operation {
        case .idle: "library.status.idle.detail"
        case .importingPhoto: "library.status.importing.detail"
        case .recording: "library.status.recording.detail"
        case .savingAudio: "library.status.saving.detail"
        case .indexing(.photo): "library.status.vision.detail"
        case .indexing(.audio): "library.status.speech.detail"
        case .complete: "library.status.complete.detail"
        case let .failed(code): failureDetail(code)
        }
    }

    private func failureDetail(_ code: EvidenceFailureCode) -> LocalizedStringKey {
        switch code {
        case .microphonePermissionDenied: "library.failure.permission"
        case .microphoneUnavailable: "library.failure.microphone"
        case .photoUnavailable: "library.failure.photo"
        case .unsupportedLanguage: "library.failure.language"
        case .speechAssetsUnavailable: "library.failure.assets"
        case .unreadableMedia: "library.failure.media"
        case .processingFailed: "library.failure.processing"
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.reportPhotoLoadFailure()
                return
            }
            let type = item.supportedContentTypes.first ?? .image
            await model.importPhoto(
                data: data,
                fileExtension: type.preferredFilenameExtension ?? "jpg",
                originalFilename: "Imported photo.\(type.preferredFilenameExtension ?? "jpg")",
                mediaTypeIdentifier: type.identifier
            )
        } catch {
            model.reportPhotoLoadFailure()
        }
    }
}

private struct EvidenceRow: View {
    let asset: CapturedEvidence

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: asset.kind == .photo ? "photo.fill" : "waveform")
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 46, height: 46)
                .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(asset.kind == .photo ? "library.kind.photo" : "library.kind.audio")
                    .font(.headline)
                Group {
                    if asset.searchableText.isEmpty {
                        Text(stateText)
                    } else {
                        Text(asset.searchableText)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Text(asset.capturedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            stateSymbol
        }
        .cardSurface()
    }

    private var stateText: LocalizedStringKey {
        switch asset.state {
        case .queued: "library.asset.queued"
        case .indexing: "library.asset.indexing"
        case .ready: "library.asset.no_text"
        case .failed: "library.asset.failed"
        }
    }

    @ViewBuilder
    private var stateSymbol: some View {
        switch asset.state {
        case .queued, .indexing:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

private struct CapturedEvidenceDetailView: View {
    let asset: CapturedEvidence
    let model: EvidenceLibraryModel
    @State private var image: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: MemoedTheme.cornerRadius))
                        .accessibilityLabel(Text("library.detail.photo.preview"))
                }

                Label(
                    asset.kind == .photo ? "library.detail.vision" : "library.detail.speech",
                    systemImage: asset.kind == .photo ? "viewfinder" : "waveform"
                )
                .font(.headline)

                if asset.kind == .photo {
                    ForEach(asset.ocrBlocks) { block in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(block.text).font(.body.weight(.medium))
                            Text(cropDescription(block.crop))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .cardSurface()
                        .accessibilityIdentifier("ocr-text-block")
                    }
                } else {
                    ForEach(asset.transcriptSpans) { span in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(span.text).font(.body.weight(.medium))
                            Text(timeDescription(span))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .cardSurface()
                        .accessibilityIdentifier("audio-transcript-span")
                    }
                }

                if asset.state == .failed {
                    Button("library.retry", systemImage: "arrow.clockwise") {
                        Task { await model.retry(asset) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(MemoedTheme.pagePadding)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(asset.kind == .photo ? "library.kind.photo" : "library.kind.audio"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard asset.kind == .photo,
                  let data = await model.data(for: asset) else { return }
            image = UIImage(data: data)
        }
    }

    private func cropDescription(_ crop: NormalizedCrop) -> String {
        String(
            format: "crop x %.3f · y %.3f · w %.3f · h %.3f",
            crop.x,
            crop.y,
            crop.width,
            crop.height
        )
    }

    private func timeDescription(_ span: AudioTranscriptSpan) -> String {
        String(
            format: "%.2fs–%.2fs",
            Double(span.startMilliseconds) / 1_000,
            Double(span.endMilliseconds) / 1_000
        )
    }
}

import SwiftUI

struct SourceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let source: DemoSource

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("source.demo.badge", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)

                    preview
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2.bold())
                        Text(excerpt)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(MemoedTheme.pagePadding)
            }
            .accessibilityIdentifier("source-detail")
            .navigationTitle(Text("source.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("source-detail-done")
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch source {
        case .correctedInvitation:
            VStack(spacing: 12) {
                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.indigo)
                Text("source.invite.crop")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .background(Color.indigo.opacity(0.10), in: RoundedRectangle(
                cornerRadius: MemoedTheme.cornerRadius,
                style: .continuous
            ))
            .accessibilityElement(children: .combine)

        case .earlierAudio, .latestAudio:
            VStack(spacing: 16) {
                HStack(spacing: 4) {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(Color.indigo.opacity(index.isMultiple(of: 3) ? 1 : 0.45))
                            .frame(width: 4, height: CGFloat(12 + (index % 5) * 7))
                    }
                }
                Label(audioInterval, systemImage: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.indigo)
            }
            .padding(30)
            .background(Color.indigo.opacity(0.10), in: RoundedRectangle(
                cornerRadius: MemoedTheme.cornerRadius,
                style: .continuous
            ))
            .accessibilityElement(children: .combine)
        }
    }

    private var title: LocalizedStringKey {
        switch source {
        case .earlierAudio: "source.old.title"
        case .correctedInvitation: "source.invite.title"
        case .latestAudio: "source.latest.title"
        }
    }

    private var excerpt: LocalizedStringKey {
        switch source {
        case .earlierAudio: "source.old.excerpt"
        case .correctedInvitation: "source.invite.excerpt"
        case .latestAudio: "source.latest.excerpt"
        }
    }

    private var audioInterval: LocalizedStringKey {
        switch source {
        case .earlierAudio: "source.old.interval"
        case .latestAudio: "source.latest.interval"
        case .correctedInvitation: "source.invite.detail"
        }
    }
}

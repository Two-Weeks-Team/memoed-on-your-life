import SwiftUI

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = HomeModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: MemoedTheme.contentSpacing) {
                        HeaderView()
                        if model.showsAnswer {
                            AnswerView(model: model)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            EmptyJourneyView(loadDemo: model.loadDemo)
                        }
                        PrivacyPledgeView()
                    }
                    .padding(.horizontal, MemoedTheme.pagePadding)
                    .padding(.bottom, 124)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(Text("app.name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.showsAnswer {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("action.reset", systemImage: "arrow.counterclockwise", action: model.reset)
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("reset-demo")
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.showsAnswer)
            .sensoryFeedback(.success, trigger: model.challengeComplete)
            .sheet(item: $model.selectedSource) { source in
                SourceDetailView(source: source)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--demo-challenged") {
                    model.loadChallengedDemo()
                } else if arguments.contains("--demo-answer") {
                    model.loadDemo()
                }
            }
        }
    }
}

private struct HeaderView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var markSize = 58.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: markSize * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: markSize, height: markSize)
                    .background(MemoedTheme.heroGradient, in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    ))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("home.eyebrow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("home.hero.title")
                        .font(.largeTitle.bold())
                        .fontDesign(.rounded)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("home.hero.subtitle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyJourneyView: View {
    let loadDemo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("demo.badge", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 10) {
                TimelineRow(symbol: "waveform", text: "demo.timeline.old")
                TimelineConnector()
                TimelineRow(symbol: "photo", text: "demo.timeline.correction")
                TimelineConnector()
                TimelineRow(symbol: "waveform.badge.plus", text: "demo.timeline.latest")
            }

            Button(action: loadDemo) {
                Label("demo.action.find", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .accessibilityIdentifier("load-demo")

            Text("demo.disclosure")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }
}

private struct TimelineRow: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.indigo)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineConnector: View {
    var body: some View {
        Capsule()
            .fill(Color.indigo.opacity(0.22))
            .frame(width: 2, height: 12)
            .padding(.leading, 11)
            .accessibilityHidden(true)
    }
}

private struct AnswerView: View {
    @Bindable var model: HomeModel

    var body: some View {
        VStack(spacing: MemoedTheme.contentSpacing) {
            SynthesisOriginBadge(origin: .onDevice)
            CurrentAnswerCard()
            ChangedFromCard(openSource: { model.selectedSource = .earlierAudio })
            WhyCurrentCard()
            SourcesCard(openSource: { model.selectedSource = $0 })
            ChallengeCard(model: model)
        }
    }
}

private struct WhyCurrentCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("answer.why.title", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text("answer.why.detail")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("why-current")
    }
}

private struct SynthesisOriginBadge: View {
    let origin: SynthesisOrigin

    var body: some View {
        Label(LocalizedStringKey(origin.localizationKey), systemImage: "iphone.gen3.radiowaves.left.and.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.indigo)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.indigo.opacity(0.1), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("answer-origin")
    }
}

private struct CurrentAnswerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("answer.current", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text("demo.badge.short")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text("answer.dinner")
                .font(.title2.bold())
                .fontDesign(.rounded)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Label("answer.prepare", systemImage: "birthday.cake.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
        }
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("current-answer")
    }
}

private struct ChangedFromCard: View {
    let openSource: () -> Void

    var body: some View {
        Button(action: openSource) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("answer.changed.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("answer.changed.value")
                        .font(.headline)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface()
        .accessibilityHint(Text("source.open.hint"))
    }
}

private struct SourcesCard: View {
    let openSource: (DemoSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("sources.title")
                .font(.headline)

            SourceButton(
                symbol: "viewfinder.rectangular",
                title: "source.invite.title",
                detail: "source.invite.detail",
                identifier: "source-corrected-invitation",
                action: { openSource(.correctedInvitation) }
            )
            Divider()
            SourceButton(
                symbol: "waveform",
                title: "source.latest.title",
                detail: "source.latest.detail",
                identifier: "source-latest-audio",
                action: { openSource(.latestAudio) }
            )
        }
        .cardSurface()
    }
}

private struct SourceButton: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityHint(Text("source.open.hint"))
    }
}

private struct ChallengeCard: View {
    @Bindable var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("challenge.title", systemImage: "shield.lefthalf.filled.badge.checkmark")
                .font(.headline)

            Text("challenge.subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let step = model.challengeStep {
                ChallengeProgressView(step: step)
            } else if model.challengeComplete {
                VStack(alignment: .leading, spacing: 12) {
                    Label("challenge.result", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("challenge-result")
                    ChallengeComparisonView()
                }
            } else {
                Button {
                    Task { await model.runChallenge() }
                } label: {
                    Label("challenge.action", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .accessibilityIdentifier("run-challenge")
            }

            Text("challenge.demo.disclosure")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }
}

private struct ChallengeComparisonView: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ComparisonVerdict(label: "challenge.before", value: "challenge.before.value")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ComparisonVerdict(label: "challenge.after", value: "challenge.after.value")
            }
            VStack(alignment: .leading, spacing: 8) {
                ComparisonVerdict(label: "challenge.before", value: "challenge.before.value")
                Divider()
                ComparisonVerdict(label: "challenge.after", value: "challenge.after.value")
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("challenge-comparison")
    }
}

private struct ComparisonVerdict: View {
    let label: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChallengeProgressView: View {
    let step: Int

    private let steps: [LocalizedStringKey] = [
        "challenge.step.search",
        "challenge.step.compare",
        "challenge.step.verify"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProgressView(value: Double(step + 1), total: Double(steps.count))
                .tint(.indigo)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                Label {
                    Text(label)
                        .foregroundStyle(index <= step ? .primary : .secondary)
                } icon: {
                    Image(systemName: index < step ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index <= step ? Color.indigo : Color.secondary.opacity(0.5))
                }
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("challenge.progress.label"))
        .accessibilityValue(Text(steps[step]))
    }
}

private struct PrivacyPledgeView: View {
    var body: some View {
        Label("privacy.pledge", systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityIdentifier("privacy-pledge")
    }
}

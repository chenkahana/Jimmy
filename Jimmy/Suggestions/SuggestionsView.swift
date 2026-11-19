import SwiftUI
import JimmyKit

/// "Up next for you" and "new shows like yours" — reached from the Queue screen's toolbar.
/// Ranked on device (`SuggestionsRanker`, in JimmyKit); when Apple's on-device model is available
/// the top 5 of each list get a model-written reason, otherwise every item keeps its plain,
/// signal-based reason and `unavailableNote` explains why.
struct SuggestionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SuggestionsViewModel?
    @State private var subscribedFeedURLs: Set<URL> = []

    var body: some View {
        content
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel == nil {
                    let vm = Self.makeViewModel(appModel: appModel)
                    viewModel = vm
                    await vm.load()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel, !viewModel.isLoading {
            if viewModel.upNext.isEmpty && viewModel.newShows.isEmpty {
                emptyState(viewModel)
            } else {
                list(viewModel)
            }
        } else {
            placeholderList
        }
    }

    /// The list's own rows, redacted, while suggestions are ranked.
    private var placeholderList: some View {
        List {
            Section("Up Next for You") {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("An episode title that fills a line")
                            .font(.body.weight(.medium))
                        Text("Show name")
                            .font(.caption)
                        Text("Why it's suggested")
                            .font(.caption)
                    }
                    .redacted(reason: .placeholder)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading Suggestions")
                    .accessibilityHidden(index != 0)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func emptyState(_ viewModel: SuggestionsViewModel) -> some View {
        VStack(spacing: 12) {
            if let note = viewModel.unavailableNote {
                unavailableBanner(note)
            }
            ContentUnavailableView {
                Label("Nothing to Suggest Yet", systemImage: "sparkles")
            } description: {
                Text("Follow a few shows and start listening — suggestions build up from there.")
            }
        }
    }

    private func unavailableBanner(_ note: String) -> some View {
        Label(note, systemImage: "sparkles")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
    }

    private func list(_ viewModel: SuggestionsViewModel) -> some View {
        List {
            if let note = viewModel.unavailableNote {
                Section {
                    Label(note, systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.upNext.isEmpty {
                Section("Up Next for You") {
                    ForEach(viewModel.upNext) { item in
                        if case .episode(let episode, let showTitle) = item.kind {
                            episodeRow(episode: episode, showTitle: showTitle, reason: item.reason)
                        }
                    }
                }
            }

            if !viewModel.newShows.isEmpty {
                Section("New Shows Like Yours") {
                    ForEach(viewModel.newShows) { item in
                        if case .show(let show) = item.kind {
                            showRow(show: show, reason: item.reason)
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(episode: JimmyKit.Episode, showTitle: String, reason: String) -> some View {
        Button {
            Task { await appModel.playNow(episode) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(showTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await appModel.queueEpisode(episode) }
            } label: {
                Label("Queue", systemImage: "text.badge.plus")
            }
            .tint(JimmyDesign.SwipeTint.queue)
        }
    }

    private func showRow(show: SuggestedShowResult, reason: String) -> some View {
        let isSubscribed = subscribedFeedURLs.contains(show.feedURL)
        return Button {
            guard !isSubscribed else { return }
            Task {
                if (try? await appModel.subscribe(feedURL: show.feedURL)) != nil {
                    subscribedFeedURLs.insert(show.feedURL)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(show.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSubscribed ? Color.accentColor : Color.secondary)
            }
        }
        .disabled(isSubscribed)
    }

    @MainActor
    private static func makeViewModel(appModel: AppModel) -> SuggestionsViewModel {
        let availability = AssistantAvailability.current()
        guard case .available = availability else {
            return SuggestionsViewModel(actions: appModel, availability: availability, session: nil)
        }
        let session = FoundationModelsSuggestionsSession()
        return SuggestionsViewModel(actions: appModel, availability: availability, session: session)
    }
}

#Preview {
    NavigationStack {
        SuggestionsView()
    }
}

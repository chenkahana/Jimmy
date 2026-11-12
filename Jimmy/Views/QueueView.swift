import SwiftUI
import TipKit
import JimmyKit

/// Renders `AppModel`'s queue (backed by JimmyKit's `Store`, the only queue now), resolved into
/// the rich per-row data (progress, played status, podcast artwork) straight from the `Store` —
/// the same `EpisodeListItem` pattern (via `observeQueueItems`) `PodcastEpisodeListView`/`LibraryView` use.
struct QueueView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editMode: EditMode = .inactive
    @State private var episodes: [Episode] = []
    @Namespace private var queueNamespace
    @State private var selectedEpisodeDestination: QueueNavigationDestination?
    @State private var showingSuggestions = false

    var body: some View {
        queueContent
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !episodes.isEmpty {
                        moreMenu
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !episodes.isEmpty {
                        EditButton()
                            .popoverTip(QueueReorderTip(), arrowEdge: .top)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSuggestions = true
                    } label: {
                        Label("Suggestions", systemImage: "lightbulb")
                    }
                }
            }
            .sheet(isPresented: $showingSuggestions) {
                NavigationStack {
                    SuggestionsView()
                }
            }
            .task {
                guard let stream = appModel.observeQueueItems() else { return }
                do {
                    // The observation already returns queue order, so it is the list's only source.
                    for try await items in stream {
                        episodes = items.map { $0.asLegacyEpisode() }
                    }
                } catch {
                    // The observation stopped (e.g. the store closed); the queue just stops updating.
                }
            }
            .navigationDestination(item: $selectedEpisodeDestination) { destination in
                EpisodeDetailView(episodeWithState: destination.episode)
                    .navigationTransition(.zoom(sourceID: destination.sourceID, in: queueNamespace))
            }
            .environment(\.editMode, $editMode)
    }

    // MARK: - View Components

    @ViewBuilder
    private var queueContent: some View {
        if episodes.isEmpty {
            EmptyStateView(
                icon: "list.bullet",
                title: "Queue Is Empty",
                subtitle: "Episodes you add appear here.",
                primaryAction: .init(label: "Browse Shows", systemImage: "magnifyingglass") {
                    DeepLinkRouter.shared.navigate(to: .discover)
                }
            )
        } else {
            queueList
        }
    }

    /// One plain list in play order. Long-press and drag (or Edit) reorders; swipes and the context
    /// menu hold the per-episode actions. The summary is a row after the last episode rather than a
    /// section footer, because plain-list footers stick to the bottom edge over a long queue.
    private var queueList: some View {
        List {
            Section {
                ForEach(episodes) { episode in
                    row(for: episode)
                }
                .onMove(perform: move)
                .onDelete { offsets in
                    for episodeID in offsets.map({ episodes[$0].id }) {
                        remove(episodeID)
                    }
                }

                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                Task { await clearPlayedEpisodes() }
            } label: {
                Label("Clear Played", systemImage: "checkmark.circle")
            }
            Button {
                Task { await appModel.shuffleQueue() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            Button(role: .destructive) {
                Task { await appModel.clearQueue() }
            } label: {
                Label("Clear All", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private func row(for episode: Episode) -> some View {
        let podcast = episode.podcastID.flatMap { podcastsByID[$0] }
        let isCurrent = appModel.playback?.currentEpisode?.id == episode.id
        let isPlaying = isCurrent && (appModel.playback?.isPlaying ?? false)
        let sourceID = "queue-episode-\(episode.id.uuidString)"
        let row = QueueEpisodeRow(
            episode: episode,
            showTitle: podcast?.title,
            showArtworkURL: podcast?.artworkURL,
            isCurrent: isCurrent,
            isPlaying: isPlaying,
            isEditing: editMode.isEditing,
            onPlay: { play(episode, isCurrent: isCurrent) }
        )

        return Button {
            showDetail(for: episode, sourceID: sourceID)
        } label: {
            row
        }
        .matchedTransitionSource(id: sourceID, in: queueNamespace)
        .accessibilityLabel(row.accessibilityText)
        .accessibilityHint("Shows episode details")
        .accessibilityAction(named: isPlaying ? "Pause" : "Play") {
            play(episode, isCurrent: isCurrent)
        }
        .swipeActions(edge: .leading) {
            playNextButton(episode)
            playedButton(episode)
        }
        .swipeActions(edge: .trailing) {
            removeButton(episode)
            downloadButton(episode)
        }
        .contextMenu {
            Button {
                play(episode, isCurrent: isCurrent)
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause" : "play")
            }
            playNextButton(episode)
            Button {
                Task { await appModel.moveToBottom(episode.id) }
            } label: {
                Label("Move to End", systemImage: "arrow.down.to.line")
            }
            playedButton(episode)
            downloadButton(episode)
            Divider()
            removeButton(episode)
        }
    }

    // MARK: - Row Actions

    private func playNextButton(_ episode: Episode) -> some View {
        Button {
            Task { await appModel.playNext(episode.id) }
        } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
    }

    private func playedButton(_ episode: Episode) -> some View {
        let isPlayed = episode.status.contains(.played)
        return Button {
            Task {
                if isPlayed {
                    await appModel.markUnplayed(episode.id)
                } else {
                    await appModel.markPlayed(episode.id)
                }
            }
        } label: {
            Label(isPlayed ? "Mark Unplayed" : "Mark Played", systemImage: isPlayed ? "circle" : "checkmark.circle")
        }
    }

    private func removeButton(_ episode: Episode) -> some View {
        Button(role: .destructive) {
            remove(episode.id)
        } label: {
            Label("Remove", systemImage: "minus.circle")
        }
    }

    /// The download action from PR #22, now a native swipe action: Download, Cancel Download while it
    /// runs, Remove Download once it's on the device.
    @ViewBuilder
    private func downloadButton(_ episode: Episode) -> some View {
        switch appModel.downloadState(for: episode.id) {
        case nil, .failed:
            Button {
                appModel.download(episode.asPlaybackEpisode())
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        case .queued, .downloading:
            Button {
                appModel.cancelDownload(episode.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        case .done:
            Button {
                appModel.deleteDownload(episode.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    private func showDetail(for episode: Episode, sourceID: String) {
        guard !editMode.isEditing else { return }
        selectedEpisodeDestination = QueueNavigationDestination(
            episode: EpisodeWithPlaybackState(
                episode: episode,
                playbackState: PlaybackState(
                    episodeID: episode.id,
                    position: episode.playbackPosition,
                    finished: episode.status.contains(.played),
                    updatedAt: Date()
                )
            ),
            sourceID: sourceID
        )
    }

    /// Plays the episode, or pauses and resumes it when it's the one already in the player.
    private func play(_ episode: Episode, isCurrent: Bool) {
        guard !editMode.isEditing else { return }
        Task {
            if isCurrent {
                await appModel.playback?.togglePlayPause()
            } else {
                await appModel.play(episode.asPlaybackEpisode())
            }
        }
    }

    private func remove(_ episodeID: UUID) {
        Motion.lightHaptic()
        episodes.removeAll { $0.id == episodeID }
        Task { await appModel.dequeue(episodeID) }
    }

    /// Applies a drop locally right away, then persists it with the same `moveInQueue` call the old
    /// drag and drop used. The haptic fires on the drop, not during the drag.
    private func move(from source: IndexSet, to destination: Int) {
        guard let fromIndex = source.first, episodes.indices.contains(fromIndex) else { return }
        let movedEpisodeID = episodes[fromIndex].id
        let newIndex = destination > fromIndex ? destination - 1 : destination
        guard newIndex != fromIndex else { return }
        episodes.move(fromOffsets: source, toOffset: destination)
        Motion.mediumHaptic()
        Task {
            await appModel.moveInQueue(movedEpisodeID, to: newIndex + 1)
            await QueueReorderTip.reorderedQueue.donate()
        }
    }

    // MARK: - Data

    private var podcastsByID: [UUID: JimmyKit.Podcast] {
        Dictionary(appModel.podcasts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// "4 episodes · 2 h 14 min left"
    private var summary: String {
        let count = episodes.count == 1 ? "1 episode" : "\(episodes.count) episodes"
        let remaining = episodes
            .filter { !$0.status.contains(.played) }
            .reduce(0) { $0 + $1.remainingTime }
        guard remaining > 0 else { return count }
        return "\(count) · \(QueueTimeFormat.duration(remaining)) left"
    }

    private func clearPlayedEpisodes() async {
        let playedEpisodeIDs = episodes.filter { $0.status.contains(.played) }.map(\.id)
        for episodeID in playedEpisodeIDs {
            await appModel.dequeue(episodeID)
        }
    }
}

private struct QueueNavigationDestination: Identifiable, Hashable {
    let episode: EpisodeWithPlaybackState
    let sourceID: String

    var id: String {
        episode.episode.id.uuidString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(episode.episode.id)
        hasher.combine(sourceID)
    }

    static func == (lhs: QueueNavigationDestination, rhs: QueueNavigationDestination) -> Bool {
        lhs.episode.episode.id == rhs.episode.episode.id && lhs.sourceID == rhs.sourceID
    }
}

#Preview {
    QueueView()
}

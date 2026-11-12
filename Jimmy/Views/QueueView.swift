import SwiftUI
import UniformTypeIdentifiers
import TipKit
import JimmyKit

/// Renders `AppModel`'s queue (backed by JimmyKit's `Store`, the only queue now), resolved into
/// the rich per-row data (progress, played status, podcast artwork) straight from the `Store` —
/// the same `EpisodeListItem` pattern (via `observeQueueItems`) `PodcastEpisodeListView`/`LibraryView` use.
struct QueueView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editMode: EditMode = .inactive
    @State private var allPodcasts: [Podcast] = []
    @State private var allEpisodeItems: [JimmyKit.EpisodeListItem] = []
    @State private var episodes: [Episode] = []
    @State private var draggedEpisode: Episode?
    @Namespace private var queueNamespace
    @State private var selectedEpisodeDestination: QueueNavigationDestination?
    @State private var showingSuggestions = false

    private var currentPlayingEpisodeID: UUID? {
        appModel.playback?.currentEpisode?.id
    }

    var body: some View {
        ZStack {
            JimmyScreenBackground()
            queueContent
        }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .onAppear {
                loadPodcasts()
            }
            .task {
                guard let stream = appModel.observeQueueItems() else { return }
                do {
                    for try await items in stream {
                        allEpisodeItems = items
                        syncEpisodesWithQueue()
                    }
                } catch {
                    // The observation stopped (e.g. the store closed); the queue just stops updating.
                }
            }
            .onChange(of: appModel.queueEpisodeIDs) { _, _ in
                syncEpisodesWithQueue()
            }
            .navigationDestination(item: $selectedEpisodeDestination) { destination in
                EpisodeDetailView(episodeWithState: destination.episode)
                    .navigationTransition(.zoom(sourceID: destination.sourceID, in: queueNamespace))
            }
    }

    // MARK: - View Components

    private var queueContent: some View {
        Group {
            if episodes.isEmpty {
                emptyStateView
            } else {
                queueList
            }
        }
    }

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "list.bullet",
            title: "Queue Is Empty",
            subtitle: "Episodes you add to your queue appear here.",
            primaryAction: .init(label: "Browse Shows", systemImage: "magnifyingglass") {
                DeepLinkRouter.shared.navigate(to: .discover)
            },
            secondaryAction: .init(label: "Open Library", systemImage: "books.vertical") {
                DeepLinkRouter.shared.navigate(to: .library)
            }
        )
    }

    private var queueList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Stats header
                QueueStatsHeader(
                    episodeCount: episodes.count,
                    totalRemainingTime: totalRemainingTime
                )

                LazyVStack(spacing: 8) {
                    // "Up Next" section (first 3 episodes)
                    if !upNextEpisodes.isEmpty {
                        sectionHeader("Up Next")
                        ForEach(Array(upNextEpisodes.enumerated()), id: \.element.id) { index, episode in
                            draggableEpisodeRow(episode: episode, index: index, isProminent: true)
                        }
                    }

                    // "Later" section (remaining episodes)
                    if !laterEpisodes.isEmpty {
                        sectionHeader("Later")
                            .padding(.top, 8)
                        ForEach(Array(laterEpisodes.enumerated()), id: \.element.id) { offset, episode in
                            let index = upNextEpisodes.count + offset
                            draggableEpisodeRow(episode: episode, index: index, isProminent: false)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !episodes.isEmpty {
                    Menu {
                        Button(action: { Task { await clearPlayedEpisodes() } }) {
                            Label("Clear Played", systemImage: "checkmark.circle")
                        }
                        Button(action: { Task { await appModel.shuffleQueue() } }) {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                        Button(role: .destructive, action: { Task { await appModel.clearQueue() } }) {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Section Helpers

    private var upNextEpisodes: [Episode] {
        Array(episodes.prefix(3))
    }

    private var laterEpisodes: [Episode] {
        Array(episodes.dropFirst(3))
    }

    private var totalRemainingTime: String {
        let totalSeconds = episodes.reduce(0) { $0 + $1.remainingTime }
        let hours = Int(totalSeconds) / 3600
        let minutes = Int(totalSeconds) % 3600 / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        JimmySectionHeader(title)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    private func draggableEpisodeRow(episode: Episode, index: Int, isProminent: Bool = false) -> some View {
        queueEpisodeRow(episode: episode, index: index, isProminent: isProminent)
            .id(episode.id)
            .onDrag {
                draggedEpisode = episode
                return NSItemProvider(object: episode.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: QueueDropDelegate(
                item: episode,
                items: $episodes,
                draggedItem: $draggedEpisode,
                onDrop: { fromIndex, toIndex in
                    guard fromIndex != toIndex, episodes.indices.contains(fromIndex) else { return }
                    let movedEpisodeID = episodes[fromIndex].id
                    let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
                    withAnimation(.motion) {
                        let moved = episodes.remove(at: fromIndex)
                        episodes.insert(moved, at: min(adjustedIndex, episodes.count))
                    }
                    Motion.mediumHaptic()
                    Task {
                        await QueueReorderTip.reorderedQueue.donate()
                        await appModel.moveInQueue(movedEpisodeID, to: adjustedIndex + 1)
                    }
                    draggedEpisode = nil
                }
            ))
    }

    private func queueEpisodeRow(episode: Episode, index: Int, isProminent: Bool = false) -> some View {
        let episodeWithStatus = convertToEpisodeWithStatus(episode, index: index)
        let isCurrentlyPlaying = currentPlayingEpisodeID == episode.id
        let sourceID = "queue-episode-\(episode.id.uuidString)"

        return QueueEpisodeCard(
            episode: episodeWithStatus,
            isCurrentlyPlaying: isCurrentlyPlaying,
            isEditMode: editMode == .active,
            isProminent: isProminent,
            downloadState: appModel.downloadState(for: episode.id),
            onTap: {
                if editMode == .inactive {
                    let episodeWithState = EpisodeWithPlaybackState(
                        episode: episode,
                        playbackState: PlaybackState(
                            episodeID: episode.id,
                            position: episode.playbackPosition,
                            finished: episode.status.contains(.played),
                            updatedAt: Date()
                        )
                    )
                    selectedEpisodeDestination = QueueNavigationDestination(
                        episode: episodeWithState,
                        sourceID: sourceID
                    )
                }
            },
            onPlay: {
                if editMode == .inactive {
                    Task { await appModel.play(episode.asPlaybackEpisode()) }
                }
            },
            onRemove: {
                Task { await appModel.dequeue(episode.id) }
            },
            onMoveToTop: {
                Task { await appModel.moveToTop(episode.id) }
            },
            onMoveToBottom: {
                Task { await appModel.moveToBottom(episode.id) }
            },
            onToggleFinished: {
                Task {
                    // Toggle finished state using the episode from queue
                    let isCurrentlyPlayed = episode.status.contains(.played)
                    if isCurrentlyPlayed {
                        await appModel.markUnplayed(episode.id)
                    } else {
                        await appModel.markPlayed(episode.id)
                    }
                }
            },
            onDownload: {
                appModel.download(episode.asPlaybackEpisode())
            },
            onCancelDownload: {
                appModel.cancelDownload(episode.id)
            },
            onDeleteDownload: {
                appModel.deleteDownload(episode.id)
            }
        )
        .matchedTransitionSource(id: sourceID, in: queueNamespace)
    }

    // MARK: - Helper Methods

    /// Convert Episode to EpisodeWithStatus for EpisodeCard
    private func convertToEpisodeWithStatus(_ episode: Episode, index: Int) -> EpisodeWithStatus {
        let podcast = getPodcast(for: episode)

        // `episode.playbackPosition`/`.duration` already carry the Store's `progress` row (see
        // `syncEpisodesWithQueue`), so no separate cache lookup is needed.
        let playProgress: Double = episode.duration.map { $0 > 0 ? episode.playbackPosition / $0 : 0.0 } ?? 0.0

        // Determine status using the derivation rules
        let isCurrentlyPlaying = (appModel.playback?.isPlaying ?? false) && appModel.playback?.currentEpisode?.id == episode.id
        let isQueued = true // Always queued since this is QueueView

        let status = EpisodeWithStatus.deriveStatus(
            episode: episode,
            playProgress: playProgress,
            isQueued: isQueued,
            isCurrentlyPlaying: isCurrentlyPlaying
        )

        return EpisodeWithStatus(
            episode: episode,
            podcastTitle: podcast?.title ?? "Unknown Podcast",
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcast?.artworkURL
        )
    }

    private func loadPodcasts() {
        // Load all podcasts for artwork lookup
        allPodcasts = (AppModel.current?.podcasts ?? []).map { $0.asLegacyPodcast() }
    }

    private func getPodcast(for episode: Episode) -> Podcast? {
        // Use preloaded podcasts for fast lookup
        return allPodcasts.first { $0.id == episode.podcastID }
    }

    /// Resolves `appModel`'s queue (ids and order) into the rich old `Episode` model this view
    /// renders, looking each one up in `allEpisodeItems` (kept current by `observeQueueItems`) and
    /// dropping anything no longer queued or not yet loaded.
    private func syncEpisodesWithQueue() {
        let itemsByID = Dictionary(uniqueKeysWithValues: allEpisodeItems.map { ($0.episode.id, $0) })
        episodes = appModel.queueEpisodeIDs.compactMap { itemsByID[$0]?.asLegacyEpisode() }
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

// MARK: - Drop Delegate for Drag and Drop Reordering
struct QueueDropDelegate: DropDelegate {
    let item: Episode
    @Binding var items: [Episode]
    @Binding var draggedItem: Episode?
    let onDrop: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedItem = draggedItem,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        if fromIndex != toIndex {
            onDrop(fromIndex, toIndex)
        }

        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        if fromIndex != toIndex {
            withAnimation(.motion) { // spring animation refactored
                items.move(fromOffsets: IndexSet([fromIndex]), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            }
        }
    }
}

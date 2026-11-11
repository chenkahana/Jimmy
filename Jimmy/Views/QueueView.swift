import SwiftUI
import UniformTypeIdentifiers
import TipKit

/// Renders `AppModel`'s queue (backed by JimmyKit's `Store`, the only queue now). The store only
/// tracks membership and order; the rich per-row data (progress, played status, podcast artwork)
/// still comes from the old episode pipeline, resolved by id as the queue's order changes.
struct QueueView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editMode: EditMode = .inactive
    @State private var allPodcasts: [Podcast] = []
    @State private var episodes: [Episode] = []
    @State private var draggedEpisode: Episode?
    @State private var episodeCache: [UUID: Episode] = [:]
    @Namespace private var queueNamespace
    @State private var selectedEpisodeDestination: QueueNavigationDestination?
    @State private var progressRefreshTick = false
    @State private var showingSuggestions = false

    var currentPlayingEpisode: Episode? {
        return appModel.playback?.currentEpisode?.asLegacyEpisode()
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
                            .font(.system(size: 16, weight: .medium))
                            .popoverTip(QueueReorderTip(), arrowEdge: .top)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSuggestions = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .accessibilityLabel("Suggestions")
                }
            }
            .sheet(isPresented: $showingSuggestions) {
                NavigationStack {
                    SuggestionsView()
                }
            }
            .onAppear {
                loadPodcasts()
                syncEpisodesWithQueue()
            }
            .onChange(of: appModel.queueEpisodeIDs) { _, _ in
                syncEpisodesWithQueue()
            }
            .onReceive(DIContainer.shared.progressCacheStore.$progressPercentageMap) { _ in
                progressRefreshTick.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .episodeStatusUpdated)) { notification in
                guard let updatedEpisode = notification.object as? Episode else { return }
                episodeCache[updatedEpisode.id] = updatedEpisode
                if let index = episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
                    episodes[index] = updatedEpisode
                }
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
            icon: "headphones.circle.fill",
            eyebrow: "Queue",
            title: "Build a listening run worth pressing play on",
            subtitle: "Save the next great episode from anywhere in Jimmy and your queue becomes the one place you can trust for what comes next.",
            primaryAction: .init(label: "Discover Podcasts", systemImage: "magnifyingglass") {
                DeepLinkRouter.shared.navigate(to: .discover)
            },
            secondaryAction: .init(label: "Browse Library", systemImage: "books.vertical") {
                DeepLinkRouter.shared.navigate(to: .library)
            }
        ) {
            JimmyCard(padding: JimmyDesign.Spacing.lg) {
                JimmySectionHeader(
                    title: "What Queue is built for",
                    detail: "Keep fresh episodes lined up, promote favorites to the top, and jump straight back into listening.",
                    icon: "sparkles"
                )

                VStack(spacing: JimmyDesign.Spacing.md) {
                    queueHighlightRow(
                        icon: "arrow.up.forward.circle.fill",
                        title: "Promote the best stuff",
                        detail: "Move must-hear episodes to the top without losing the rest of your stack."
                    )
                    queueHighlightRow(
                        icon: "play.circle.fill",
                        title: "Pick up instantly",
                        detail: "Playback state and artwork stay visible so the next decision is effortless."
                    )
                }
            }
            .frame(maxWidth: 640)
        }
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
                        sectionHeader("Up Next", icon: "play.circle")
                        ForEach(Array(upNextEpisodes.enumerated()), id: \.element.id) { index, episode in
                            draggableEpisodeRow(episode: episode, index: index, isProminent: true)
                                .staggeredAppear(index: index)
                                .scrollEdgeTransition()
                        }
                    }

                    // "Later" section (remaining episodes)
                    if !laterEpisodes.isEmpty {
                        sectionHeader("Later", icon: "clock")
                            .padding(.top, 8)
                        ForEach(Array(laterEpisodes.enumerated()), id: \.element.id) { offset, episode in
                            let index = upNextEpisodes.count + offset
                            draggableEpisodeRow(episode: episode, index: index, isProminent: false)
                                .staggeredAppear(index: offset)
                                .scrollEdgeTransition()
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
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
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

    private func sectionHeader(_ title: String, icon: String) -> some View {
        JimmySectionHeader(
            title: title,
            icon: icon,
            trailingText: title == "Up Next" ? "Ready first" : "Queued"
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func queueHighlightRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: JimmyDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(JimmyDesign.Typography.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
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
        let isCurrentlyPlaying = currentPlayingEpisode?.id == episode.id
        let sourceID = "queue-episode-\(episode.id.uuidString)"

        return QueueEpisodeCard(
            episode: episodeWithStatus,
            isCurrentlyPlaying: isCurrentlyPlaying,
            isEditMode: editMode == .active,
            isProminent: isProminent,
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
                        var newStatus = episode.status
                        newStatus.remove(.played)
                        EpisodeService.shared.updateEpisodeStatus(episode, status: newStatus)
                    } else {
                        EpisodeService.shared.setEpisodePlayed(episode)
                    }
                }
            }
        )
        .matchedTransitionSource(id: sourceID, in: queueNamespace)
    }

    // MARK: - Helper Methods

    /// Convert Episode to EpisodeWithStatus for EpisodeCard
    private func convertToEpisodeWithStatus(_ episode: Episode, index: Int) -> EpisodeWithStatus {
        _ = progressRefreshTick

        let podcast = getPodcast(for: episode)
        let progressCache = DIContainer.shared.progressCacheStore

        // Calculate play progress - use real-time cache first, then fallback
        let playProgress: Double

        // CRITICAL FIX: Update progress cache with episode duration FIRST
        if episode.duration != nil && episode.duration! > 0 {
            progressCache.updateProgressPercentage(for: episode.id, duration: episode.duration!)
        }

        // CRITICAL FIX: Check if episode exists in cache (including 0% progress)
        // Don't use > 0 check because 0% is valid progress
        if progressCache.hasProgress(for: episode.id) {
            // Episode is in cache - use cached value (could be 0% or any value)
            playProgress = progressCache.getProgressPercentage(for: episode.id)
        } else {
            // Episode not in cache - fallback to episode's stored position
            playProgress = episode.duration != nil && episode.duration! > 0
                ? episode.playbackPosition / episode.duration!
                : 0.0
        }



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
    /// renders, fetching anything not already cached and dropping anything no longer queued.
    private func syncEpisodesWithQueue() {
        let orderedIDs = appModel.queueEpisodeIDs
        Task {
            var resolved: [Episode] = []
            for episodeID in orderedIDs {
                if let cached = episodeCache[episodeID] {
                    resolved.append(cached)
                    continue
                }
                if let episodeWithState = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) {
                    episodeCache[episodeID] = episodeWithState.episode
                    resolved.append(episodeWithState.episode)
                }
            }
            await MainActor.run {
                self.episodes = resolved
            }
        }
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

import SwiftUI
import os
import JimmyKit

struct LibraryView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LibraryView")
    @Environment(AppModel.self) private var appModel
    @Environment(ShellStore.self) private var shell
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .shows

    @State private var searchText: String = ""
    @State private var isAddingSamplePodcasts = false

    @State private var allEpisodeItems: [JimmyKit.EpisodeListItem] = []
    @State private var newEpisodeCounts: [UUID: Int] = [:]
    @State private var isLoadingEpisodes = false
    @State private var episodesObservationTask: Task<Void, Never>?

    @State private var selectedDestination: LibraryNavigationDestination?
    @Namespace private var libraryNamespace

    @State private var podcastToUnsubscribe: JimmyKit.Podcast?

    /// Narrowest a grid cell gets; three across on iPhone, fewer as text grows.
    @ScaledMetric(relativeTo: .subheadline) private var minimumCellWidth: CGFloat = 100

    enum LibraryViewMode: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }

    var body: some View {
        mainContentView
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: viewMode == .shows ? "Search Shows" : "Search Episodes"
            )
            .toolbar {
                if isLoadingEpisodes {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                            .accessibilityLabel("Loading episodes")
                    }
                }
            }
            .onAppear {
                startObservingEpisodesIfNeeded()
                Task {
                    await handlePendingContentRouteIfNeeded()
                    await validateAndPreloadArtwork()
                }
            }
            .onChange(of: shell.pendingContentRoute?.id) { _, _ in
                Task { await handlePendingContentRouteIfNeeded() }
            }
            .onChange(of: shell.tabSelectionEventID) { _, _ in
                guard shell.selectedTab == .library, shell.pendingContentRoute == nil else { return }
                selectedDestination = nil
            }
            .onChange(of: jimmyKitPodcasts) { _, podcasts in
                newEpisodeCounts = LibraryShowCell.newEpisodeCounts(episodes: allEpisodeItems, podcasts: podcasts)
            }
            .navigationDestination(item: $selectedDestination) { destination in
                switch destination {
                case .podcast(let podcastID, let cachedPodcast, let sourceID):
                    ResolvedPodcastDetailView(
                        podcastID: podcastID,
                        cachedPodcast: cachedPodcast,
                        sourceID: sourceID,
                        namespace: libraryNamespace
                    )
                case .episode(let episodeID, let cachedEpisode, let sourceID):
                    ResolvedEpisodeDetailView(
                        episodeID: episodeID,
                        cachedEpisode: cachedEpisode,
                        sourceID: sourceID,
                        namespace: libraryNamespace
                    )
                }
            }
            .alert(
                "Unsubscribe from \(podcastToUnsubscribe?.title ?? "Show")?",
                isPresented: Binding(
                    get: { podcastToUnsubscribe != nil },
                    set: { if !$0 { podcastToUnsubscribe = nil } }
                ),
                presenting: podcastToUnsubscribe
            ) { podcast in
                Button("Cancel", role: .cancel) {}
                Button("Unsubscribe", role: .destructive) {
                    Task { await unsubscribe(podcast.id) }
                }
            } message: { _ in
                Text("This will remove the podcast from your library and delete all downloaded episodes.")
            }
    }

    // MARK: - Data

    /// The subscribed podcasts, kept current by `AppModel.podcasts` (observing JimmyKit's
    /// `Store` directly) — already sorted newest-episode-first. This is what fixed the
    /// "Add sample podcasts" empty-library bug: there's no separate cache to refresh.
    private var jimmyKitPodcasts: [JimmyKit.Podcast] { appModel.podcasts }

    /// `allEpisodeItems` converted to the legacy `Jimmy.Episode` model (with progress/played/queue
    /// state baked in), for the view code below that still renders the old `EpisodeCard`/
    /// `EpisodeWithStatus`.
    private var allEpisodes: [Jimmy.Episode] {
        allEpisodeItems.map { $0.asLegacyEpisode() }
    }

    private var filteredPodcasts: [JimmyKit.Podcast] {
        guard !searchText.isEmpty else { return jimmyKitPodcasts }
        return jimmyKitPodcasts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// The 100 most recent episodes, narrowed by the search text (episode or show title).
    private var recentEpisodeItems: [JimmyKit.EpisodeListItem] {
        guard !searchText.isEmpty else { return Array(allEpisodeItems.prefix(100)) }
        let matchingShowIDs = Set(filteredPodcasts.map(\.id))
        let matches = allEpisodeItems.filter { item in
            item.episode.title.localizedCaseInsensitiveContains(searchText) ||
            item.episode.podcastID.map(matchingShowIDs.contains) == true
        }
        return Array(matches.prefix(100))
    }

    private func unsubscribe(_ podcastID: UUID) async {
        await appModel.unsubscribe(podcastID)
        allEpisodeItems.removeAll { $0.episode.podcastID == podcastID }
    }

    #if DEBUG
    private func deleteAllPodcasts() async {
        for podcast in jimmyKitPodcasts {
            await appModel.unsubscribe(podcast.id)
        }
        allEpisodeItems = []
    }
    #endif

    private func refreshLibrary() async {
        // `apply`'s writes land in the store, which `episodesObservationTask` is already
        // subscribed to — no separate reload needed once this returns.
        await appModel.refreshAll()
    }

    /// Subscribes once to every episode across the whole library (joined with progress, queue
    /// membership, and download state), for the "Episodes" view mode and the grid's new-episode
    /// counts — re-emitted live as any of that changes, straight from `AppModel`'s `Store`.
    private func startObservingEpisodesIfNeeded() {
        guard episodesObservationTask == nil else { return }
        guard let stream = appModel.observeEpisodes(podcastID: nil) else { return }

        isLoadingEpisodes = true
        episodesObservationTask = Task {
            do {
                for try await items in stream {
                    allEpisodeItems = items
                    newEpisodeCounts = LibraryShowCell.newEpisodeCounts(episodes: items, podcasts: jimmyKitPodcasts)
                    isLoadingEpisodes = false
                }
            } catch {
                logger.error("LibraryView: observeEpisodes stopped: \(error)")
                isLoadingEpisodes = false
            }
        }
    }

    // MARK: - Chrome

    /// The first row under the large title. In the navigation bar's center it would replace the
    /// large title and push the search field away.
    private var viewModePicker: some View {
        Picker("View", selection: $viewMode) {
            ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var refreshErrorsRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Couldn't refresh ^[\(appModel.lastRefreshErrors.count) show](inflect: true).")
                .foregroundStyle(.secondary)
            Spacer(minLength: JimmyDesign.Spacing.sm)
            Button("Try Again") {
                Task { await refreshLibrary() }
            }
        }
        .font(.footnote)
    }

    // MARK: - Content

    @ViewBuilder
    private var mainContentView: some View {
        if jimmyKitPodcasts.isEmpty {
            if isLoadingEpisodes {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyStateView
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
                    viewModePicker

                    if !appModel.lastRefreshErrors.isEmpty {
                        refreshErrorsRow
                    }

                    switch viewMode {
                    case .shows: showsGrid
                    case .episodes: episodesList
                    }
                }
                .padding(.horizontal, JimmyDesign.Spacing.lg)
                .padding(.top, JimmyDesign.Spacing.sm)
                .tabBarBottomPadding()
            }
            .refreshable { await refreshLibrary() }
            .overlay { contentUnavailableOverlay }
        }
    }

    @ViewBuilder
    private var contentUnavailableOverlay: some View {
        switch viewMode {
        case .shows:
            if filteredPodcasts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        case .episodes:
            if recentEpisodeItems.isEmpty && !isLoadingEpisodes {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Episodes",
                        systemImage: "waveform",
                        description: Text("Episodes from the shows you follow appear here.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Shows Grid

    private var showsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumCellWidth), spacing: JimmyDesign.Spacing.md, alignment: .top)],
            alignment: .leading,
            spacing: JimmyDesign.Spacing.xl
        ) {
            ForEach(filteredPodcasts) { podcast in
                let sourceID = "library-show-\(podcast.id.uuidString)"
                Button {
                    selectedDestination = .podcast(id: podcast.id, cachedPodcast: podcast.asLegacyPodcast(), sourceID: sourceID)
                } label: {
                    LibraryShowCell(
                        podcast: podcast,
                        newEpisodeCount: newEpisodeCounts[podcast.id] ?? 0,
                        transitionID: sourceID,
                        namespace: libraryNamespace
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Unsubscribe", systemImage: "minus.circle", role: .destructive) {
                        podcastToUnsubscribe = podcast
                    }
                    #if DEBUG
                    Button("Unsubscribe from All", systemImage: "trash", role: .destructive) {
                        Task { await deleteAllPodcasts() }
                    }
                    #endif
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Unsubscribe") {
                    podcastToUnsubscribe = podcast
                }
            }
        }
    }

}

// MARK: - Episodes List

extension LibraryView {

    private var episodesList: some View {
        LazyVStack(spacing: JimmyDesign.Spacing.sm) {
            ForEach(recentEpisodesWithStatus, id: \.id) { episodeWithStatus in
                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        let episode = allEpisodes.first { $0.id == episodeWithStatus.id }
                        if let episode {
                            let sourceID = "library-episode-\(episode.id.uuidString)"
                            let episodeWithState = EpisodeWithPlaybackState(
                                episode: episode,
                                playbackState: PlaybackState(episodeID: episode.id, position: 0, finished: false, updatedAt: Date())
                            )
                            selectedDestination = .episode(id: episode.id, cachedEpisode: episodeWithState, sourceID: sourceID)
                        }
                    },
                    onPlay: {
                        Task {
                            if let episode = allEpisodes.first(where: { $0.id == episodeWithStatus.id }) {
                                await playEpisode(episode)
                            }
                        }
                    },
                    onAddToQueue: {
                        if let episode = allEpisodes.first(where: { $0.id == episodeWithStatus.id }) {
                            addToQueue(episode)
                        }
                    },
                    onToggleFinished: {
                        if let episode = allEpisodes.first(where: { $0.id == episodeWithStatus.id }) {
                            toggleFinished(episode)
                        }
                    }
                )
                .matchedTransitionSource(id: "library-episode-\(episodeWithStatus.id.uuidString)", in: libraryNamespace)
            }
        }
    }

    private var recentEpisodesWithState: [EpisodeWithPlaybackState] {
        Array(allEpisodeItems.prefix(100)).map { item in
            EpisodeWithPlaybackState(
                episode: item.asLegacyEpisode(),
                playbackState: PlaybackState(
                    episodeID: item.episode.id,
                    position: item.progress?.position ?? 0,
                    finished: item.progress?.isFinished ?? false,
                    updatedAt: Date()
                )
            )
        }
    }

    private var recentEpisodesWithStatus: [EpisodeWithStatus] {
        let playback = appModel.playback

        return recentEpisodeItems.map { item in
            let episode = item.asLegacyEpisode()
            let podcast = jimmyKitPodcasts.first { $0.id == episode.podcastID }
            let podcastTitle = podcast?.title ?? "Unknown Podcast"

            let duration = item.progress?.duration ?? episode.duration
            let playProgress: Double
            if let duration, duration > 0 {
                playProgress = (item.progress?.position ?? 0) / duration
            } else {
                playProgress = 0.0
            }

            let isCurrentlyPlaying = (playback?.isPlaying ?? false) && playback?.currentEpisode?.id == episode.id

            let status = EpisodeWithStatus.deriveStatus(
                episode: episode,
                playProgress: playProgress,
                isQueued: item.isQueued,
                isCurrentlyPlaying: isCurrentlyPlaying
            )

            return EpisodeWithStatus(
                episode: episode,
                podcastTitle: podcastTitle,
                playProgress: playProgress,
                status: status,
                podcastArtworkURL: podcast?.artworkURL
            )
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "books.vertical",
            title: "No Shows Yet",
            subtitle: "Shows you follow appear here.",
            primaryAction: .init(label: "Browse Shows", systemImage: "magnifyingglass") {
                DeepLinkRouter.shared.navigate(to: .discover)
            },
            secondaryAction: .init(label: isAddingSamplePodcasts ? "Adding Sample Shows…" : "Add Sample Shows", systemImage: "plus") {
                guard !isAddingSamplePodcasts else { return }
                Task {
                    isAddingSamplePodcasts = true
                    await addSamplePodcasts()
                    isAddingSamplePodcasts = false
                }
            }
        )
    }

    // MARK: - Episode Actions

    private func playEpisode(_ episode: Jimmy.Episode) async {
        await appModel.play(episode.asPlaybackEpisode())
    }

    private func addToQueue(_ episode: Jimmy.Episode) {
        Task { await appModel.enqueue(episode.id) }
    }

    private func toggleFinished(_ episode: Jimmy.Episode) {
        Task {
            if episode.status.contains(.played) {
                await appModel.markUnplayed(episode.id)
            } else {
                await appModel.markPlayed(episode.id)
            }
        }
    }

    @MainActor
    private func handlePendingContentRouteIfNeeded() async {
        guard let route = shell.pendingContentRoute else { return }

        switch route {
        case .podcast(let podcastID):
            viewMode = .shows
            let cachedPodcast = jimmyKitPodcasts.first(where: { $0.id == podcastID })?.asLegacyPodcast()
            selectedDestination = .podcast(id: podcastID, cachedPodcast: cachedPodcast, sourceID: "library-show-\(podcastID.uuidString)")

        case .episode(let episodeID):
            viewMode = .episodes
            let cachedEpisode = recentEpisodesWithState.first(where: { $0.episode.id == episodeID })
            selectedDestination = .episode(id: episodeID, cachedEpisode: cachedEpisode, sourceID: "library-episode-\(episodeID.uuidString)")
        }

        shell.clearPendingContentRoute(route)
    }

    // MARK: - Helper Methods

    private func validateAndPreloadArtwork() async {
        let podcasts = jimmyKitPodcasts
        guard !podcasts.isEmpty else { return }

        let visiblePodcasts = Array(podcasts.prefix(9))
        let priorityURLs = Set(visiblePodcasts.compactMap { $0.artworkURL })

        if !priorityURLs.isEmpty {
            BulletproofImageCache.shared.preloadImages(urls: priorityURLs)
            let remainingURLs = Set(podcasts.compactMap { $0.artworkURL }).subtracting(priorityURLs)
            if !remainingURLs.isEmpty {
                Task(priority: .background) {
                    BulletproofImageCache.shared.preloadImages(urls: remainingURLs)
                }
            }
        }
    }

    /// Adds a handful of popular podcasts, in parallel, to help a new user get started — each
    /// one goes straight through `AppModel.subscribe(feedURL:)`, so it shows up in the grid the
    /// moment it's written (no separate "refresh the library" step needed).
    private func addSamplePodcasts() async {
        let sampleFeedURLs = [
            "https://feeds.nytimes.com/nyt/rss/podcasts/the-daily",
            "https://feeds.thisamericanlife.org/talpodcast",
            "https://feeds.serialpodcast.org/serial",
            "https://feeds.wnyc.org/radiolab",
            "https://feeds.npr.org/510289/podcast.xml"
        ].compactMap { URL(string: $0) }

        await withTaskGroup(of: Void.self) { group in
            for feedURL in sampleFeedURLs {
                group.addTask { _ = try? await appModel.subscribe(feedURL: feedURL) }
            }
        }
        // `episodesObservationTask` (started in `.onAppear`) picks up the newly-subscribed
        // podcasts' episodes on its own — no separate reload needed.
    }
}

// MARK: - Preview

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environment(ShellStore.shared)
    }
}

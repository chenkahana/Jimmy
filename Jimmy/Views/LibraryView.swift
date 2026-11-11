import SwiftUI
import os
import JimmyKit

struct LibraryView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LibraryView")
    @Environment(AppModel.self) private var appModel
    @Environment(ShellStore.self) private var shell
    @State private var toastMessage: String = ""
    @State private var showToast: Bool = false
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .shows
    @AppStorage("libraryShowsOverviewDismissed") private var isShowsOverviewDismissed = false
    @AppStorage("libraryEpisodesOverviewDismissed") private var isEpisodesOverviewDismissed = false

    @State private var searchText: String = ""
    @State private var isEditMode: Bool = false
    @State private var isAddingSamplePodcasts = false

    @State private var allEpisodeItems: [JimmyKit.EpisodeListItem] = []
    @State private var isLoadingEpisodes = false
    @State private var episodesObservationTask: Task<Void, Never>?

    @State private var selectedDestination: LibraryNavigationDestination?
    @Namespace private var libraryNamespace

    // Unsubscribe confirmation
    @State private var podcastToUnsubscribe: Podcast?
    @State private var showUnsubscribeAlert = false

    // Grid layout state
    @State private var gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm),
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm),
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm)
    ]
    @State private var layoutReady = false
    @State private var gridInitialized = false

    enum LibraryViewMode: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }

    var body: some View {
        ZStack {
            JimmyScreenBackground()

            VStack(spacing: 0) {
                if showsLibraryChrome {
                    if shouldShowLibraryOverviewHeader {
                        libraryOverviewHeader
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    searchBar
                    viewModeToggle
                }

                if isLoadingEpisodes {
                    streamingProgressBanner
                }

                if !appModel.lastRefreshErrors.isEmpty {
                    refreshErrorsBanner
                }

                mainContentView
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .animation(.motionGentle, value: shouldShowLibraryOverviewHeader)
        .onAppear {
            if !gridInitialized {
                initializeGridLayout()
            }
            if !jimmyKitPodcasts.isEmpty {
                Task { await validateAndPreloadArtwork() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isEditMode.toggle() }) {
                    Text(isEditMode ? "Done" : "Edit")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                #if DEBUG
                if isEditMode {
                    Menu {
                        Button("Delete All", role: .destructive) {
                            Task { await deleteAllPodcasts() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.red)
                    }
                }
                #endif
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
        .refreshable {
            await refreshLibrary()
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
        .alert("Unsubscribe from \(podcastToUnsubscribe?.title ?? "Podcast")?", isPresented: $showUnsubscribeAlert) {
            Button("Cancel", role: .cancel) {
                podcastToUnsubscribe = nil
            }
            Button("Unsubscribe", role: .destructive) {
                if let podcast = podcastToUnsubscribe {
                    Task { await unsubscribe(podcast) }
                }
                podcastToUnsubscribe = nil
            }
        } message: {
            Text("This will remove the podcast from your library and delete all downloaded episodes.")
        }
        .overlay(
            VStack {
                Spacer()
                if showToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.motionTransition, value: showToast)
                }
            }
        )
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

    private var filteredPodcasts: [Podcast] {
        let podcasts = jimmyKitPodcasts.map { $0.asLegacyPodcast() }
        guard !searchText.isEmpty else { return podcasts }
        return podcasts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.author.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func unsubscribe(_ podcast: Podcast) async {
        await appModel.unsubscribe(podcast.id)
        await MainActor.run {
            allEpisodeItems.removeAll { $0.episode.podcastID == podcast.id }
            toastMessage = "Unsubscribed"
            showToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showToast = false
            }
        }
    }

    private func deleteAllPodcasts() async {
        for podcast in jimmyKitPodcasts {
            await appModel.unsubscribe(podcast.id)
        }
        await MainActor.run { allEpisodeItems = [] }
    }

    private func refreshLibrary() async {
        // `apply`'s writes land in the store, which `episodesObservationTask` is already
        // subscribed to — no separate reload needed once this returns.
        await appModel.refreshAll()
    }

    /// Subscribes once to every episode across the whole library (joined with progress, queue
    /// membership, and download state), for the "Episodes" view mode — re-emitted live as any of
    /// that changes, straight from `AppModel`'s `Store`.
    private func startObservingEpisodesIfNeeded() {
        guard episodesObservationTask == nil else { return }
        guard let stream = appModel.observeEpisodes(podcastID: nil) else { return }

        isLoadingEpisodes = true
        episodesObservationTask = Task {
            do {
                for try await items in stream {
                    allEpisodeItems = items
                    isLoadingEpisodes = false
                }
            } catch {
                logger.error("LibraryView: observeEpisodes stopped: \(error)")
                isLoadingEpisodes = false
            }
        }
    }

    // MARK: - Toast View

    private var toastView: some View {
        HStack {
            Text(toastMessage)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .tabBarBottomPadding()
    }

    // MARK: - Streaming Progress Banner

    private var showsLibraryChrome: Bool {
        isLoadingEpisodes || !jimmyKitPodcasts.isEmpty || !allEpisodes.isEmpty
    }

    private var libraryOverviewHeader: some View {
        JimmyCard(isHighlighted: viewMode == .shows && !jimmyKitPodcasts.isEmpty, padding: JimmyDesign.Spacing.lg) {
            JimmySectionHeader(
                eyebrow: "Collection",
                title: viewMode == .shows ? "Your shows" : "Recent episodes",
                subtitle: libraryOverviewSubtitle,
                icon: viewMode == .shows ? "books.vertical.fill" : "waveform.path"
            ) {
                if hasLibraryContent {
                    Button(action: dismissLibraryOverviewHeader) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss library summary")
                    .accessibilityHint("Hides this library summary card")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var shouldShowLibraryOverviewHeader: Bool {
        if !hasLibraryContent { return true }
        return !currentOverviewDismissed
    }

    private var hasLibraryContent: Bool {
        !jimmyKitPodcasts.isEmpty || !allEpisodes.isEmpty
    }

    private var libraryOverviewSubtitle: String {
        if jimmyKitPodcasts.isEmpty && allEpisodes.isEmpty {
            return "Follow standout podcasts, import an existing lineup, or sample a few shows to get started."
        }
        return "\(jimmyKitPodcasts.count) shows • \(allEpisodes.count) episodes ready for quick browsing."
    }

    private var currentOverviewDismissed: Bool {
        switch viewMode {
        case .shows: return isShowsOverviewDismissed
        case .episodes: return isEpisodesOverviewDismissed
        }
    }

    private func dismissLibraryOverviewHeader() {
        Motion.lightHaptic()
        switch viewMode {
        case .shows: isShowsOverviewDismissed = true
        case .episodes: isEpisodesOverviewDismissed = true
        }
    }

    private var streamingProgressBanner: some View {
        JimmyCard(padding: JimmyDesign.Spacing.md) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)

                Text("Loading Episodes")
                    .font(JimmyDesign.Typography.caption)
                    .fontWeight(.medium)

                Spacer()

                Text("\(allEpisodes.count)")
                    .font(JimmyDesign.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.motionGentle, value: isLoadingEpisodes)
    }

    private var refreshErrorsBanner: some View {
        JimmyCard(padding: JimmyDesign.Spacing.md) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Couldn't refresh \(appModel.lastRefreshErrors.count) show\(appModel.lastRefreshErrors.count == 1 ? "" : "s")")
                    .font(JimmyDesign.Typography.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        LibrarySearchComponent(searchText: $searchText, placeholder: "Search podcasts, episodes, creators")
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        JimmyCard(padding: JimmyDesign.Spacing.sm) {
            Picker("View Mode", selection: $viewMode) {
                ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Library view mode")
            .accessibilityHint("Select between Shows grid and Episodes list")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .shows: showsGridView
        case .episodes: episodesListView
        }
    }

    // MARK: - Shows Grid View

    private var showsGridView: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(filteredPodcasts, id: \.id) { podcast in
                        ZStack {
                            Button {
                                let sourceID = "library-show-\(podcast.id.uuidString)"
                                selectedDestination = .podcast(id: podcast.id, cachedPodcast: podcast, sourceID: sourceID)
                            } label: {
                                OptimizedPodcastCard(podcast: podcast, isEditMode: false, onUnsubscribe: {})
                                    .matchedTransitionSource(id: "library-show-\(podcast.id.uuidString)", in: libraryNamespace)
                            }
                            .disabled(isEditMode)
                            .buttonStyle(.plain)

                            if isEditMode {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Button(action: {
                                            podcastToUnsubscribe = podcast
                                            showUnsubscribeAlert = true
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.red).frame(width: 24, height: 24))
                                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .accessibilityLabel("Unsubscribe from \(podcast.title)")
                                        .accessibilityHint("Double tap to remove this podcast from your library")
                                        .offset(x: 8, y: -8)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .scaleEffect(isEditMode ? 0.95 : 1.0)
                        .animation(.motionGentle, value: isEditMode)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: filteredPodcasts.count)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .tabBarBottomPadding()
            }
            .refreshable { await refreshLibrary() }
            .scrollContentBackground(.hidden)
            .onAppear {
                updateGridColumns(width: geometry.size.width)
                layoutReady = true
            }
            .onChange(of: Int(geometry.size.width / 10)) { _, _ in
                if layoutReady { updateGridColumns(width: geometry.size.width) }
            }
        }
    }

    private func updateGridColumns(width: CGFloat) {
        let minItemWidth: CGFloat = 164
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 32
        let availableWidth = width - horizontalPadding
        let count = max(3, Int((availableWidth + spacing) / (minItemWidth + spacing)))
        gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
        gridInitialized = true
    }

    private func initializeGridLayout() {
        let screenWidth = UIScreen.main.bounds.width
        updateGridColumns(width: screenWidth)
        layoutReady = true
    }

    // MARK: - Episodes List View

    private var episodesListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !allEpisodes.isEmpty || isLoadingEpisodes {
                    episodesSectionHeader
                }

                if recentEpisodesWithStatus.isEmpty && !isLoadingEpisodes {
                    VStack(spacing: 16) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Episodes Available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Episodes will appear here as they load from your subscribed podcasts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 60)
                } else {
                    Section {
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

                if isLoadingEpisodes {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading more episodes...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .tabBarBottomPadding()
        }
        .scrollContentBackground(.hidden)
    }

    private var episodesSectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Episodes")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("\(allEpisodes.count) episodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isLoadingEpisodes {
                ProgressView().scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Computed Properties

    @ViewBuilder
    private var mainContentView: some View {
        if isLoadingEpisodes && jimmyKitPodcasts.isEmpty && allEpisodes.isEmpty {
            loadingView
        } else if jimmyKitPodcasts.isEmpty {
            emptyStateView
        } else {
            contentView
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
        let recentItems = Array(allEpisodeItems.prefix(100))
        let playback = appModel.playback

        return recentItems.map { item in
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

    // MARK: - Loading View

    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Loading Library...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                if viewMode == .shows {
                    LazyVGrid(columns: gridColumns, spacing: JimmyDesign.Spacing.sm) {
                        ForEach(0..<9, id: \.self) { _ in
                            LiquidSkeletonView(style: .libraryGrid)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<8, id: \.self) { _ in
                            LiquidSkeletonView(style: .episodeRow)
                        }
                    }
                }
            }
            .tabBarSpacing()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "waveform.circle.fill",
            eyebrow: "Library",
            title: "Build a podcast shelf that feels curated",
            subtitle: "Follow a few standout shows, import what you already love, and Jimmy will keep recent episodes within reach.",
            primaryAction: .init(label: "Discover Podcasts", systemImage: "magnifyingglass") {
                DeepLinkRouter.shared.navigate(to: .discover)
            }
        ) {
            JimmyCard(padding: JimmyDesign.Spacing.lg) {
                JimmySectionHeader(
                    title: "Quick start",
                    detail: "Seed the library with a few sample podcasts so you can explore the full experience immediately.",
                    icon: "sparkles"
                )

                Button {
                    Task {
                        isAddingSamplePodcasts = true
                        await addSamplePodcasts()
                        isAddingSamplePodcasts = false
                    }
                } label: {
                    HStack(spacing: JimmyDesign.Spacing.sm) {
                        if isAddingSamplePodcasts {
                            ProgressView().scaleEffect(0.8).tint(.accentColor)
                        } else {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                        }
                        Text(isAddingSamplePodcasts ? "Adding sample podcasts..." : "Add sample podcasts")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, JimmyDesign.Spacing.md)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAddingSamplePodcasts)
            }
        }
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
                Task.detached(priority: .background) {
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

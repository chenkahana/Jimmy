import SwiftUI
import os

struct LibraryView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LibraryView")
    @ObservedObject private var viewModel = LibraryViewModel.shared
    @ObservedObject private var subscriptionViewModel = SubscriptionViewModel.shared // For toast messages only
    @Environment(ShellStore.self) private var shell
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .shows
    @AppStorage("libraryShowsOverviewDismissed") private var isShowsOverviewDismissed = false
    @AppStorage("libraryEpisodesOverviewDismissed") private var isEpisodesOverviewDismissed = false
    
    // Enhanced UX engines
    @StateObject private var predictiveEngine = PredictiveUserBehaviorEngine.shared
    @State private var isAddingSamplePodcasts = false
    
    @State private var selectedDestination: LibraryNavigationDestination?
    @Namespace private var libraryNamespace
    
    // Unsubscribe confirmation
    @State private var podcastToUnsubscribe: Podcast?
    @State private var showUnsubscribeAlert = false
    @State private var removingPodcastIDs: Set<UUID> = [] // Track podcasts being removed
    @State private var viewRefreshTrigger = false // Force SwiftUI to refresh computed properties
    
    // Grid layout state
    @State private var gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm),
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm),
        GridItem(.flexible(), spacing: JimmyDesign.Spacing.sm)
    ]
    @State private var layoutReady = false
    @State private var gridInitialized = false
    @State private var gridLayoutState = GridLayoutState()
    
    enum LibraryViewMode: String, CaseIterable {
        case shows = "Shows"
        case episodes = "Episodes"
    }
    
    struct GridLayoutState {
        var isInitialized: Bool = false
        var columnCount: Int = 3
        var lastCalculatedWidth: CGFloat = 0
        var initializationAttempts: Int = 0
        var maxInitializationAttempts: Int = 3
        
        mutating func markInitialized(columnCount: Int, width: CGFloat) {
            self.isInitialized = true
            self.columnCount = columnCount
            self.lastCalculatedWidth = width
        }
        
        mutating func recordAttempt() {
            initializationAttempts += 1
        }
        
        var shouldRetry: Bool {
            return !isInitialized && initializationAttempts < maxInitializationAttempts
        }
        
        mutating func reset() {
            isInitialized = false
            initializationAttempts = 0
            lastCalculatedWidth = 0
        }
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

                if viewModel.isStreamingEpisodes {
                    streamingProgressBanner
                }

                mainContentView
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .animation(.motionGentle, value: shouldShowLibraryOverviewHeader)
        .performanceAdaptive(baseSkeletonCount: 9)
        .onAppear {
            // Initialize grid layout immediately
            if !gridInitialized {
                initializeGridLayout()
            }
            
            // Preload artwork immediately if data is already available
            if !viewModel.podcasts.isEmpty {
                Task {
                    await validateAndPreloadArtwork()
                }
            }
            
            // Track user behavior for predictive loading
            predictiveEngine.trackAction(.libraryBrowse)
            
            // Safety timeout for loading state
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if viewModel.isLoading && viewModel.podcasts.isEmpty {
                    // Force clear loading state if stuck
                    await MainActor.run {
                        viewModel.isLoading = false
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    viewModel.toggleEditMode()
                }) {
                    Text(viewModel.isEditMode ? "Done" : "Edit")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                #if DEBUG
                if viewModel.isEditMode {
                    Menu {
                        Button("Delete All", role: .destructive) {
                            Task {
                                await viewModel.resetDatabase()
                            }
                        }
                        
                        Button("Force Resort") {
                            viewModel.forceResort()
                        }
                        
                        Button("Debug Legacy Data") {
                            viewModel.debugLegacyDataSources()
                        }
                        
                        Button("Force Migration Flag") {
                            viewModel.forceMigrationCompleted()
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
            // Only perform expensive operations if we don't already have data
            let hasData = !viewModel.podcasts.isEmpty || !viewModel.allEpisodes.isEmpty
            
            Task {
                await handlePendingContentRouteIfNeeded()
                await viewModel.loadDataIfNeeded()
                
                // Only force reload if we truly have no episodes but have podcasts
                if viewModel.allEpisodes.isEmpty && !viewModel.podcasts.isEmpty {
                    await forceLoadAllEpisodes()
                    
                    // Force SwiftUI to re-evaluate computed properties
                    await MainActor.run {
                        viewRefreshTrigger.toggle()
                    }
                }
                
                // Only refresh playback states if we don't already have data
                // This prevents unnecessary database queries on every navigation
                if !hasData {
                    await refreshEpisodesWithPlaybackStates()
                }
                
                // CRITICAL FIX: Validate and preload podcast images after data loads
                // This ensures images appear even when network issues occurred during initial load
                await validateAndPreloadArtwork()
            }
        }
        .onChange(of: shell.pendingContentRoute?.id) { _, _ in
            Task {
                await handlePendingContentRouteIfNeeded()
            }
        }
        .onChange(of: shell.tabSelectionEventID) { _, _ in
            guard shell.selectedTab == .library, shell.pendingContentRoute == nil else {
                return
            }
            selectedDestination = nil
        }
        .onReceive(DIContainer.shared.progressCacheStore.$progressPercentageMap) { _ in
            viewRefreshTrigger.toggle()
        }
        .onChange(of: viewModel.refreshID) { _, _ in
            viewRefreshTrigger.toggle()
        }
        .refreshable {
            await viewModel.refreshData()
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
                    Task {
                        await viewModel.removePodcast(podcast)
                        
                        // Show toast message
                        await MainActor.run {
                            subscriptionViewModel.toastMessage = "Unsubscribed"
                            subscriptionViewModel.showToast = true
                            
                            // Hide toast after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                subscriptionViewModel.showToast = false
                            }
                        }
                    }
                }
                podcastToUnsubscribe = nil
            }
        } message: {
            Text("This will remove the podcast from your library and delete all downloaded episodes.")
        }
        .overlay(
            // Toast overlay for subscription feedback
            VStack {
                Spacer()
                if subscriptionViewModel.showToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.motionTransition, value: subscriptionViewModel.showToast) // spring animation refactored
                }
            }
        )
    }
    
    // MARK: - Toast View
    
    private var toastView: some View {
        HStack {
            Text(subscriptionViewModel.toastMessage)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Spacer()
            
            if subscriptionViewModel.pendingDeleteShowID != nil {
                Button("Undo") {
                    Task {
                        await subscriptionViewModel.undoUnsubscribe()
                    }
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .tabBarBottomPadding() // Account for tab bar using new spacing system
    }
    
    // MARK: - Streaming Progress Banner

    private var showsLibraryChrome: Bool {
        viewModel.isLoading || viewModel.isStreamingEpisodes || !viewModel.podcasts.isEmpty || !viewModel.allEpisodes.isEmpty
    }

    private var libraryOverviewHeader: some View {
        JimmyCard(isHighlighted: viewMode == .shows && !viewModel.podcasts.isEmpty, padding: JimmyDesign.Spacing.lg) {
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
        if !hasLibraryContent {
            return true
        }

        return !currentOverviewDismissed
    }

    private var hasLibraryContent: Bool {
        !viewModel.podcasts.isEmpty || !viewModel.allEpisodes.isEmpty
    }

    private var libraryOverviewSubtitle: String {
        if viewModel.podcasts.isEmpty && viewModel.allEpisodes.isEmpty {
            return "Follow standout podcasts, import an existing lineup, or sample a few shows to get started."
        }

        return "\(viewModel.podcasts.count) shows • \(viewModel.allEpisodes.count) episodes ready for quick browsing."
    }

    private var currentOverviewDismissed: Bool {
        switch viewMode {
        case .shows:
            return isShowsOverviewDismissed
        case .episodes:
            return isEpisodesOverviewDismissed
        }
    }

    private func dismissLibraryOverviewHeader() {
        Motion.lightHaptic()

        switch viewMode {
        case .shows:
            isShowsOverviewDismissed = true
        case .episodes:
            isEpisodesOverviewDismissed = true
        }
    }

    private var streamingProgressBanner: some View {
        JimmyCard(padding: JimmyDesign.Spacing.md) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading Episodes")
                        .font(JimmyDesign.Typography.caption)
                        .fontWeight(.medium)

                    Text(viewModel.streamingProgress)
                        .font(JimmyDesign.Typography.detail)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(viewModel.allEpisodes.count)")
                    .font(JimmyDesign.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.motionGentle, value: viewModel.isStreamingEpisodes) // spring animation refactored
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        LibrarySearchComponent(
            searchText: $viewModel.searchText,
            placeholder: "Search podcasts, episodes, creators"
        )
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
        case .shows:
            showsGridView
        case .episodes:
            episodesListView
        }
    }
    
    // MARK: - Optimized Shows Grid View
    
    private var showsGridView: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(
                    columns: gridColumns,
                    spacing: 16
                ) {
                    // Beautiful skeleton loading with liquid animations
                    if viewModel.isLoading && viewModel.podcasts.isEmpty {
                        ForEach(0..<9, id: \.self) { index in
                            LiquidSkeletonView(style: .libraryGrid)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: viewModel.isLoading)
                        }
                    } else {
                        ForEach(sortedPodcasts.filter { !removingPodcastIDs.contains($0.id) }, id: \.id) { podcast in
                            ZStack {
                                Button {
                                    let sourceID = "library-show-\(podcast.id.uuidString)"
                                    selectedDestination = .podcast(
                                        id: podcast.id,
                                        cachedPodcast: podcast,
                                        sourceID: sourceID
                                    )
                                } label: {
                                    OptimizedPodcastCard(
                                        podcast: podcast,
                                        isEditMode: false, // Don't show X button in the card itself
                                        onUnsubscribe: { } // Empty closure since we handle it outside
                                    )
                                    .matchedTransitionSource(id: "library-show-\(podcast.id.uuidString)", in: libraryNamespace)
                                }
                                .disabled(viewModel.isEditMode)
                                .buttonStyle(.plain) // Prevent button animations during scroll

                                
                                // X button overlay when in edit mode - outside NavigationLink
                                if viewModel.isEditMode {
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
                                                    .background(
                                                        Circle()
                                                            .fill(Color.red)
                                                            .frame(width: 24, height: 24)
                                                    )
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
                            .scaleEffect(viewModel.isEditMode ? 0.95 : 1.0)
                            .animation(.motionGentle, value: viewModel.isEditMode) // spring animation refactored
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                removal: .opacity
                            ))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: sortedPodcasts.count)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .tabBarBottomPadding() // Use new spacing system instead of hardcoded 100
            }
            .refreshable {
                // Use progressive loading for smooth show-by-show updates
                await viewModel.refreshWithProgressiveLoading()
            }
            .scrollContentBackground(.hidden)

            .onAppear {
                updateGridColumns(width: geometry.size.width)
                layoutReady = true
            }
            .onChange(of: Int(geometry.size.width / 10)) { _, _ in
                if layoutReady {
                    updateGridColumns(width: geometry.size.width)
                }
            }
        }
    }
    
    private func updateGridColumns(width: CGFloat) {
        let minItemWidth: CGFloat = 164
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 32 // 16 on each side
        let availableWidth = width - horizontalPadding
        let count = max(3, Int((availableWidth + spacing) / (minItemWidth + spacing))) // Start with minimum 3 columns
        
        gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
        gridLayoutState.markInitialized(columnCount: count, width: width)
        gridInitialized = true
    }
    
    private func initializeGridLayout() {
        gridLayoutState.recordAttempt()
        
        // Force immediate layout calculation with default screen width
        let screenWidth = UIScreen.main.bounds.width
        updateGridColumns(width: screenWidth)
        layoutReady = true
        
        // Add timeout fallback
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !gridLayoutState.isInitialized && gridLayoutState.shouldRetry {
                await MainActor.run {
                    useDefaultGridLayout()
                }
            }
        }
    }
    
    private func useDefaultGridLayout() {
        // Fallback to default 3-column layout
        let spacing: CGFloat = 12
        gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3)
        gridLayoutState.markInitialized(columnCount: 3, width: UIScreen.main.bounds.width)
        gridInitialized = true
        layoutReady = true
        
        logger.debug("LibraryView: Using default 3-column grid layout as fallback")
    }
    
    private func resetGridLayoutState() {
        gridLayoutState.reset()
        gridInitialized = false
        layoutReady = false
    }
    
    // MARK: - Episodes List View
    
    private var episodesListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Show episode count and streaming status
                if !viewModel.allEpisodes.isEmpty || viewModel.isStreamingEpisodes {
                    episodesSectionHeader
                }
                
                if recentEpisodesWithStatus.isEmpty && !viewModel.isStreamingEpisodes {
                    // Show message when no episodes are available
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
                        // Unified EpisodeCard component
                        ForEach(recentEpisodesWithStatus, id: \.id) { episodeWithStatus in
                            EpisodeCard(
                                episode: episodeWithStatus,
                                onTap: {
                                    // Handle episode detail navigation
                                    let episode = viewModel.allEpisodes.first { $0.id == episodeWithStatus.id }
                                    if let episode = episode {
                                        let sourceID = "library-episode-\(episode.id.uuidString)"
                                        let episodeWithState = EpisodeWithPlaybackState(
                                            episode: episode,
                                            playbackState: PlaybackState(
                                                episodeID: episode.id,
                                                position: 0,
                                                finished: false,
                                                updatedAt: Date()
                                            )
                                        )
                                        selectedDestination = .episode(
                                            id: episode.id,
                                            cachedEpisode: episodeWithState,
                                            sourceID: sourceID
                                        )
                                    }
                                },
                                onPlay: {
                                    Task {
                                        let episode = viewModel.allEpisodes.first { $0.id == episodeWithStatus.id }
                                        if let episode = episode {
                                            await playEpisode(episode)
                                        }
                                    }
                                },
                                onAddToQueue: {
                                    let episode = viewModel.allEpisodes.first { $0.id == episodeWithStatus.id }
                                    if let episode = episode {
                                        addToQueue(episode)
                                    }
                                },
                                onToggleFinished: {
                                    let episode = viewModel.allEpisodes.first { $0.id == episodeWithStatus.id }
                                    if let episode = episode {
                                        toggleFinished(episode)
                                    }
                                }
                            )
                            .matchedTransitionSource(id: "library-episode-\(episodeWithStatus.id.uuidString)", in: libraryNamespace)
                        }
                    }
                }
                
                // Show loading indicator if streaming
                if viewModel.isStreamingEpisodes {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading more episodes...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .tabBarBottomPadding() // Use new spacing system instead of hardcoded 100
        }
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Episodes Section Header
    
    private var episodesSectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Episodes")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if viewModel.isStreamingEpisodes {
                    Text(viewModel.streamingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.allEpisodes.count) episodes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if viewModel.isStreamingEpisodes {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    // MARK: - Computed Properties
    
    @ViewBuilder
    private var mainContentView: some View {
        if viewModel.isLoading && viewModel.podcasts.isEmpty && viewModel.allEpisodes.isEmpty {
            loadingView
                .onAppear {
                    // Additional safety: auto-clear loading after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        if viewModel.isLoading && viewModel.podcasts.isEmpty {
                            viewModel.isLoading = false
                        }
                    }
                }
        } else if viewModel.podcasts.isEmpty {
            emptyStateView
        } else {
            contentView
        }
    }
    
    // Cached sorted podcasts to prevent recomputation during scroll
    private var sortedPodcasts: [Podcast] {
        // Sort podcasts locally by latest episode date without triggering async engine
        // This prevents the endless logging and improves performance
        let podcasts = viewModel.filteredPodcasts
        
        return podcasts.sorted { podcast1, podcast2 in
            // Get latest episode date for each podcast
            let episodes1 = viewModel.getEpisodes(for: podcast1)
            let episodes2 = viewModel.getEpisodes(for: podcast2)
            
            let latestDate1 = episodes1.compactMap { $0.publishedDate }.max() ?? Date.distantPast
            let latestDate2 = episodes2.compactMap { $0.publishedDate }.max() ?? Date.distantPast
            
            return latestDate1 > latestDate2
        }
    }
    
    private var recentEpisodesWithState: [EpisodeWithPlaybackState] {

        let recentEpisodes = viewModel.getRecentEpisodes(limit: 100)
        
        return recentEpisodes.map { episode in
            EpisodeWithPlaybackState(
                episode: episode,
                playbackState: PlaybackState(
                    episodeID: episode.id,
                    position: 0,
                    finished: false,
                    updatedAt: Date()
                )
            )
        }
    }
    
    /// Convert episodes to EpisodeWithStatus for the new EpisodeCard component
    private var recentEpisodesWithStatus: [EpisodeWithStatus] {
        // Force recomputation by depending on refresh trigger
        _ = viewRefreshTrigger
        
        // FALLBACK: Use LibraryViewModel episodes for now (sync approach)
        // TODO: Make this async to use database directly like QueueView
        let recentEpisodes = viewModel.getRecentEpisodes(limit: 100)
        let audioPlayer = AudioPlayerService.shared
        let progressCache = DIContainer.shared.progressCacheStore
        
        return recentEpisodes.map { episode in
            
            // Get podcast title
            let podcast = viewModel.podcasts.first { $0.id == episode.podcastID }
            let podcastTitle = podcast?.title ?? "Unknown Podcast"
            
            // Calculate play progress - use real-time cache first, then fallback
            let playProgress: Double
            
            // CRITICAL FIX: Update progress cache with episode duration FIRST
            if let duration = episode.duration, duration > 0 {
                progressCache.updateProgressPercentage(for: episode.id, duration: duration)
            }
            
            // Get the updated cached progress percentage
            let cachedProgressPercentage = progressCache.getProgressPercentage(for: episode.id)
            
            // CRITICAL FIX: Check if episode exists in cache (including 0% progress)
            // Don't use > 0 check because 0% is valid progress
            if progressCache.hasProgress(for: episode.id) {
                // Episode is in cache - use cached value (could be 0% or any value)
                playProgress = cachedProgressPercentage
            } else {
                // Episode not in cache - fallback to episode's stored position
                if let duration = episode.duration, duration > 0 {
                    playProgress = episode.playbackPosition / duration
                } else {
                    playProgress = 0.0
                }
            }
            

            
            // Determine status using the derivation rules
            let isCurrentlyPlaying = audioPlayer.isPlaying && audioPlayer.currentEpisode?.id == episode.id
            let isQueued = AppModel.current?.isQueued(episode.id) ?? false
            
            let status = EpisodeWithStatus.deriveStatus(
                episode: episode,
                playProgress: playProgress,
                isQueued: isQueued,
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
                // Loading message
                VStack(spacing: 8) {
                    Text("Loading Library...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if viewModel.isStreamingEpisodes {
                        Text(viewModel.streamingProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                
                // Skeleton content based on view mode
                if viewMode == .shows {
                    // Grid skeleton for shows
                    LazyVGrid(columns: gridColumns, spacing: JimmyDesign.Spacing.sm) {
                        ForEach(0..<9, id: \.self) { index in
                            LiquidSkeletonView(style: .libraryGrid)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: viewModel.isLoading
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    // List skeleton for episodes
                    LazyVStack(spacing: 12) {
                        ForEach(0..<8, id: \.self) { index in
                            LiquidSkeletonView(style: .episodeRow)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: viewModel.isLoading
                                )
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
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.accentColor)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
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
    
    private func playEpisode(_ episode: Episode) async {
        // Use AudioPlayerService to load and play the episode
        let audioPlayerService = AudioPlayerService.shared
        await MainActor.run {
            audioPlayerService.loadEpisode(episode, startPlaying: true)
        }
    }
    
    private func addToQueue(_ episode: Episode) {
        // Add episode to queue
        Task {
            await AppModel.current?.enqueue(episode.id)
        }
    }
    
    private func toggleFinished(_ episode: Episode) {
        // Toggle the finished state of the episode and update status
        Task {
            // First try to get the episode with current status from database
            let episodeWithStatus = try? await EpisodeService.shared.getEpisodeWithStatus(episode)
            let actualEpisode = episodeWithStatus ?? episode
            
            // Check current played status and toggle it
            let isCurrentlyPlayed = actualEpisode.status.contains(.played)
            
            if isCurrentlyPlayed {
                // Remove played status
                var newStatus = actualEpisode.status
                newStatus.remove(.played)
                EpisodeService.shared.updateEpisodeStatus(actualEpisode, status: newStatus)
            } else {
                // Mark as played
                EpisodeService.shared.setEpisodePlayed(actualEpisode)
            }
        }
    }

    @MainActor
    private func handlePendingContentRouteIfNeeded() async {
        guard let route = shell.pendingContentRoute else {
            return
        }

        switch route {
        case .podcast(let podcastID):
            viewMode = .shows
            let cachedPodcast = viewModel.podcasts.first(where: { $0.id == podcastID }) ??
                PodcastService.shared.loadPodcasts().first(where: { $0.id == podcastID })
            selectedDestination = .podcast(
                id: podcastID,
                cachedPodcast: cachedPodcast,
                sourceID: "library-show-\(podcastID.uuidString)"
            )

        case .episode(let episodeID):
            viewMode = .episodes
            let cachedEpisode = recentEpisodesWithState.first(where: { $0.episode.id == episodeID })
            selectedDestination = .episode(
                id: episodeID,
                cachedEpisode: cachedEpisode,
                sourceID: "library-episode-\(episodeID.uuidString)"
            )
        }

        shell.clearPendingContentRoute(route)
    }
    
        // MARK: - Helper Methods

    /// Force load all episodes from database when LibraryViewModel has podcasts but no episodes
    private func forceLoadAllEpisodes() async {
        // Get all episodes from database directly
        let episodeRepository = DIContainer.shared.episodeRepository
        var allEpisodes: [Episode] = []
        
        for podcast in viewModel.podcasts {
            do {
                let episodesWithState = try await episodeRepository.fetchEpisodes(for: podcast.id, ignoreCache: true)
                let episodes = episodesWithState.map { $0.episode }
                allEpisodes.append(contentsOf: episodes)
            } catch {
                logger.error("LibraryView: Failed to load episodes for podcast \(podcast.title): \(error)")
            }
        }
        
        // Update the viewModel with the loaded episodes sorted by date
        await MainActor.run {
            viewModel.allEpisodes = allEpisodes.sorted { 
                ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast)
            }
        }
    }
    
    private func fetchEpisodesInBackground(for podcasts: [Podcast]) async {
        // Fetch episodes for all podcasts in parallel
        await withTaskGroup(of: Void.self) { group in
            for podcast in podcasts {
                group.addTask {
                    do {
                        // Use the podcast service to fetch episodes for this podcast
                        let podcastService = DIContainer.shared.podcastService
                        _ = try await podcastService.addPodcast(from: podcast.feedURL)
                    } catch {
                        // Handle error silently
                    }
                }
            }
        }
        
        // Refresh the library one more time after all episodes are loaded
        await viewModel.refreshData()
    }

    /// Refresh episodes with playback states from database (same as QueueView)
    private func refreshEpisodesWithPlaybackStates() async {
        // Force LibraryViewModel to reload episodes with proper playback states from database
        // This ensures consistency with QueueView data
        await viewModel.refreshData()
    }
    
    /// Force preload images for all podcasts to ensure they appear
    private func preloadPodcastImages() async {
        let podcasts = viewModel.podcasts
        guard !podcasts.isEmpty else { return }
        
        // Extract artwork URLs
        let artworkURLs = Set(podcasts.compactMap { $0.artworkURL })
        guard !artworkURLs.isEmpty else { return }
        
        // Use BulletproofImageCache to preload in background
        BulletproofImageCache.shared.preloadImages(urls: artworkURLs)
    }
    
    private func validateAndPreloadArtwork() async {
        // Trigger immediate image cache warming for visible items
        let podcasts = viewModel.podcasts
        guard !podcasts.isEmpty else { return }
        
        // Prioritize artwork for first 9 items (likely visible in 3x3 grid)
        let visiblePodcasts = Array(podcasts.prefix(9))
        let priorityURLs = Set(visiblePodcasts.compactMap { $0.artworkURL })
        
        if !priorityURLs.isEmpty {
            // Preload priority images first
            BulletproofImageCache.shared.preloadImages(urls: priorityURLs)
            
            // Then preload remaining images in background
            let remainingURLs = Set(podcasts.compactMap { $0.artworkURL }).subtracting(priorityURLs)
            if !remainingURLs.isEmpty {
                Task.detached(priority: .background) {
                    BulletproofImageCache.shared.preloadImages(urls: remainingURLs)
                }
            }
        }
    }
    
    private func addSamplePodcasts() async {
        // Add some popular, well-known podcasts to help users get started
        let samplePodcasts = [
            ("The Daily", "https://feeds.nytimes.com/nyt/rss/podcasts/the-daily", "The New York Times"),
            ("This American Life", "https://feeds.thisamericanlife.org/talpodcast", "This American Life"),
            ("Serial", "https://feeds.serialpodcast.org/serial", "Serial Productions"),
            ("Radiolab", "https://feeds.wnyc.org/radiolab", "WNYC Studios"),
            ("Planet Money", "https://feeds.npr.org/510289/podcast.xml", "NPR")
        ]
        
        // Create podcasts immediately without fetching episodes (fast)
        let podcasts = samplePodcasts.compactMap { (title, feedURLString, author) -> Podcast? in
            guard let feedURL = URL(string: feedURLString) else { return nil }
            return Podcast(
                id: UUID(),
                title: title,
                author: author,
                description: "Popular podcast - episodes will load shortly",
                feedURL: feedURL,
                artworkURL: nil,
                lastEpisodeDate: nil,
                etag: nil,
                lastFetched: nil
            )
        }
        
        // Add podcasts to database immediately (very fast)
        do {
            let subscriptionRepository = DIContainer.shared.subscriptionRepository
            for podcast in podcasts {
                try await subscriptionRepository.addSubscription(podcast)
            }
            
            // Refresh the library immediately to show the new podcasts
            await viewModel.refreshData()
            
            // Now fetch episodes in parallel in the background (slow but non-blocking)
            await fetchEpisodesInBackground(for: podcasts)
            
        } catch {
            // Handle error silently
        }
    }
    
}

// MARK: - Preview

struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environment(ShellStore.shared)
    }
}

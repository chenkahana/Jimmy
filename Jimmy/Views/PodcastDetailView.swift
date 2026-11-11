import SwiftUI
import UIKit
import os

// MARK: - Async Podcast Detail View Wrapper
/// This view handles loading full podcast data from RSS feed for Discovery results
/// Ensures Discovery and Library views show identical information
struct AsyncPodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AsyncPodcastDetailView")
    let searchResult: PodcastSearchResult
    @State private var podcast: Podcast?
    @State private var episodes: [Episode] = [] // Add episodes state
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if isLoading {
                podcastDetailLoadingView
            } else if let podcast = podcast {
                PreviewPodcastDetailView(
                    podcast: podcast,
                    episodes: episodes // Pass episodes to the view
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Error Loading Podcast")
                        .font(.headline)
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Try Again") {
                        loadPodcast()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .onAppear {
            loadPodcast()
        }
    }
    
    private func loadPodcast() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // PREVIEW ONLY: Load podcast data WITHOUT saving to database
                // Use the GRDB repository for proper RSS parsing
                let grdbRepo = DIContainer.shared.podcastRepository
                let (podcastData, episodesData) = try await grdbRepo.previewPodcastWithEpisodes(from: searchResult.feedURL)
                
                await MainActor.run {
                    self.podcast = podcastData
                    self.episodes = episodesData // Store the episodes
                    self.isLoading = false
                }
                
                logger.info("Podcast preview loaded: \(podcastData.title) with \(episodesData.count) episodes (not saved)")
                
            } catch {
                logger.error("Failed to load podcast: \(error)")
                
                // Final fallback: Create minimal podcast object for display
                await MainActor.run {
                    let minimalPodcast = Podcast(
                        title: searchResult.title,
                        author: searchResult.author,
                        description: searchResult.description ?? "",
                        feedURL: searchResult.feedURL,
                        artworkURL: searchResult.artworkURL
                    )
                    
                    self.podcast = minimalPodcast
                    self.episodes = [] // No episodes for minimal fallback
                    self.isLoading = false
                    
                    logger.warning("Using minimal podcast data for preview")
                }
            }
        }
    }
    
    // MARK: - Enhanced Loading View
    
    private var podcastDetailLoadingView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header skeleton
                VStack(spacing: 16) {
                    // Large artwork skeleton
                    LiquidSkeletonView(style: .podcastCard)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    VStack(spacing: 8) {
                        // Title skeleton
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 28)
                            .frame(maxWidth: 280)
                        
                        // Author skeleton
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 20)
                            .frame(maxWidth: 200)
                    }
                }
                .padding(.top, 60)
                
                // Episodes section skeleton
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        // "Episodes" title skeleton
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 24)
                        
                        Spacer()
                        
                        // Filter button skeleton
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 20)
                    
                    // Episode list skeleton
                    LazyVStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            LiquidSkeletonView(style: .episodeRow)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: true
                                )
                        }
                    }
                }
                .padding(.top, 20)
            }
            .tabBarSpacing()
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            // Back button skeleton
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Spacer()
                
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 90)
        }
    }
}

// MARK: - Preview-specific PodcastDetailView

struct PreviewPodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PreviewPodcastDetailView")
    let podcast: Podcast
    let episodes: [Episode]
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var gradientOpacity: Double = 1.0
    @State private var showingDescriptionSheet = false
    @State private var selectedEpisode: EpisodeWithPlaybackState?
    @StateObject private var swipeStateManager = SwipeStateManager.shared
    @State private var subscriptionError: SubscriptionError?
    @State private var isSubscribing = false
    
    // Filter and sort options
    @State private var filterOption: PodcastDetailViewModel.EpisodeFilter = .all
    @State private var sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst
    
    private let headerHeight: CGFloat = 400
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Main scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 50pt spacer to align all content with artwork offset
                        Spacer()
                            .frame(height: 50)
                        
                        // Collapsible artwork header with title/author overlay
                        CollapsibleHeaderView(
                            podcast: podcast,
                            headerHeight: headerHeight,
                            minHeight: 80,
                            scrollOffset: scrollOffset
                        )
                        .overlay(alignment: .top) {
                            // Top gradient overlay for header
                            GradientOverlay(edge: .top)
                                .frame(height: 70)
                                .opacity(gradientOpacity)
                                .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                        }
                        .overlay(alignment: .bottom) {
                            // Title and Author overlaid on artwork
                            VStack(spacing: 8) {
                                Text(podcast.cleanTitle.isEmpty ? podcast.title : podcast.cleanTitle)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 20)

                                Text(podcast.author.isEmpty ? "No Author" : podcast.author)
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 20)
                        }
                        
                        // Episodes content
                        previewEpisodesContent
                            .padding(.top, 8)
                            .background(
                                VStack {
                                    Spacer()
                                    GradientOverlay(edge: .bottom)
                                        .frame(height: 50)
                                        .opacity(gradientOpacity * 0.6)
                                        .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                                }
                            )
                    }
                    .tabBarSpacing() // Add proper bottom spacing for tab bar
                }
                .coordinateSpace(name: "scroll")
                .background(Color(.systemBackground))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }

            .overlay(alignment: .top) {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                    .offset(y: 30) 
                    
                    Spacer()
                    
                    Menu {
                        // "About" button
                        if !podcast.description.isEmpty {
                            Button(action: { showingDescriptionSheet = true }) {
                                Label("About", systemImage: "info.circle")
                            }
                        }
                        
                        // Subscribe button for preview
                        let isSubscribed = appModel.podcasts.contains { $0.feedURL == podcast.feedURL }
                        let isProcessing = isSubscribing
                        
                        if isSubscribed {
                            Button(action: { 
                                // Already subscribed - no action
                            }) {
                                Label("Subscribed", systemImage: "checkmark.circle.fill")
                            }
                            .disabled(true)
                        } else {
                            Button(action: { 
                                Task { await subscribeToPodcast() }
                            }) {
                                Label(isProcessing ? "Subscribing..." : "Subscribe", systemImage: "plus")
                            }
                            .disabled(isProcessing)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                    .offset(y: 30) 
                }
                .padding(.horizontal, 20)
                .padding(.top, geometry.safeAreaInsets.top + 30)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: $showingDescriptionSheet) {
            PodcastDescriptionView(
                podcast: podcast,
                onDismiss: { showingDescriptionSheet = false }
            )
        }
        .background(
            NavigationLink(
                destination: selectedEpisode.map { EpisodeDetailView(episodeWithState: $0) },
                isActive: Binding(
                    get: { selectedEpisode != nil },
                    set: { if !$0 { selectedEpisode = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
    }
    
    // MARK: - Preview Episodes Content
    private var previewEpisodesContent: some View {
        VStack(spacing: 0) {
            // Episodes header with filter/sort controls
            HStack {
                Text("Episodes")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Filter and sort menu
                Menu {
                    // Filter options
                    Menu("Filter Episodes") {
                        Button(action: { filterOption = .all }) {
                            Label("All Episodes", systemImage: filterOption == .all ? "checkmark" : "")
                        }
                        Button(action: { filterOption = .unplayed }) {
                            Label("Unplayed", systemImage: filterOption == .unplayed ? "checkmark" : "")
                        }
                        Button(action: { filterOption = .played }) {
                            Label("Played", systemImage: filterOption == .played ? "checkmark" : "")
                        }
                    }
                    
                    // Sort options
                    Menu("Sort Episodes") {
                        Button(action: { sortOrder = .newestFirst }) {
                            Label("Newest First", systemImage: sortOrder == .newestFirst ? "checkmark" : "")
                        }
                        Button(action: { sortOrder = .oldestFirst }) {
                            Label("Oldest First", systemImage: sortOrder == .oldestFirst ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            // Episodes list - Use preview episodes directly
            PreviewEpisodeListView(
                episodes: episodes,
                podcastTitle: podcast.title,
                podcastArtworkURL: podcast.artworkURL,
                filterOption: filterOption,
                sortOrder: sortOrder,
                onEpisodeTap: { episodeWithState in
                    swipeStateManager.closeAllSwipeActions()
                    selectedEpisode = episodeWithState
                }
            )
            .clipped()
        }
        .background(Color(.systemBackground))
    }
    
    private func subscribeToPodcast() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            _ = try await appModel.subscribe(feedURL: podcast.feedURL)
            logger.info("Subscribed to podcast: \(podcast.title)")
        } catch {
            subscriptionError = .unknownError(error.localizedDescription)
            logger.error("Unexpected error subscribing to podcast: \(error)")
        }
    }
}

// MARK: - Preview Episode List View

struct PreviewEpisodeListView: View {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PreviewEpisodeListView")
    @Environment(AppModel.self) private var appModel
    let episodes: [Episode]
    let podcastTitle: String
    let podcastArtworkURL: URL?
    let filterOption: PodcastDetailViewModel.EpisodeFilter
    let sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    let onEpisodeTap: (EpisodeWithPlaybackState) -> Void
    
    var body: some View {
        Group {
            if episodes.isEmpty {
                emptyView
            } else {
                episodesList
            }
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Episodes Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("This podcast may not have any episodes yet.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var episodesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredAndSortedEpisodes, id: \.id) { episode in
                let episodeWithStatus = convertToEpisodeWithStatus(episode)
                
                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        let episodeWithState = EpisodeWithPlaybackState(
                            episode: episode,
                            playbackState: PlaybackState(
                                episodeID: episode.id,
                                position: episode.playbackPosition,
                                finished: episode.played || episode.status.contains(.played),
                                updatedAt: Date()
                            )
                        )
                        onEpisodeTap(episodeWithState)
                    },
                    onPlay: {
                        Task { await appModel.play(episode.asPlaybackEpisode()) }
                    },
                    onAddToQueue: {
                        Task {
                            await AppModel.current?.enqueue(episode.id)
                        }
                    },
                    onToggleFinished: {
                        // For preview episodes, we can't toggle played status since they're not in database
                        Self.logger.warning("Cannot toggle played status for preview episodes")
                    }
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Data Processing
    
    private var filteredAndSortedEpisodes: [Episode] {
        var filtered = episodes
        
        // Apply filter
        switch filterOption {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { !$0.played && !$0.status.contains(.played) }
        case .played:
            filtered = filtered.filter { $0.played || $0.status.contains(.played) }
        case .downloaded:
            filtered = filtered.filter { $0.localFileURL != nil }
        }
        
        // Apply sort
        switch sortOrder {
        case .newestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        case .oldestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) }
        case .titleAZ:
            filtered.sort { $0.title < $1.title }
        case .titleZA:
            filtered.sort { $0.title > $1.title }
        }
        
        return filtered
    }
    
    private func convertToEpisodeWithStatus(_ episode: Episode) -> EpisodeWithStatus {
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
            podcastArtworkURL: podcastArtworkURL
        )
    }
}

struct PodcastDetailView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastDetailView")
    let podcast: Podcast
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var gradientOpacity: Double = 1.0
    @State private var showingDescriptionSheet = false
    @State private var selectedEpisode: EpisodeWithPlaybackState? // Add selectedEpisode state for navigation
    @StateObject private var swipeStateManager = SwipeStateManager.shared

    // Subscription management
    @State private var showingUnsubscribeAlert = false
    @State private var subscriptionError: SubscriptionError?
    @State private var isSubscribing = false
    
    // Filter and sort options
    @State private var filterOption: PodcastDetailViewModel.EpisodeFilter = .all
    @State private var sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst
    
    private let headerHeight: CGFloat = 400

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Main scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // 50pt spacer to align all content with artwork offset
                        Spacer()
                            .frame(height: 50)
                        
                        // Collapsible artwork header with title/author overlay
                        CollapsibleHeaderView(
                            podcast: podcast,
                            headerHeight: headerHeight,
                            minHeight: 80,
                            scrollOffset: scrollOffset
                        )
                        .overlay(alignment: .top) {
                            // Top gradient overlay for header
                            GradientOverlay(edge: .top)
                                .frame(height: 70) // Set to 70pt
                                .opacity(gradientOpacity)
                                .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                        }
                        .overlay(alignment: .bottom) {
                            // Title and Author overlaid on artwork
                            VStack(spacing: 8) {

                                Text(podcast.cleanTitle.isEmpty ? podcast.title : podcast.cleanTitle)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 20)

                                Text(podcast.author.isEmpty ? "No Author" : podcast.author)
                                    .font(.title2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
                                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                    .padding(.horizontal, 20)
                            }
                            .padding(.bottom, 20) // Increased padding for better spacing
                        }
                        
                        // Episodes content with bottom gradient as background
                        episodesContent
                            .padding(.top, 8)
                            .background(
                                // Bottom gradient overlay positioned behind episodes content - increased opacity
                                VStack {
                                    Spacer()
                                    GradientOverlay(edge: .bottom)
                                        .frame(height: 50) // Reduced from 150pt to 105pt (70%)
                                        .opacity(gradientOpacity * 0.6) // Increased opacity to 60%
                                        .animation(.easeInOut(duration: 0.4), value: gradientOpacity)
                                }
                            )
                    }
                }
                .coordinateSpace(name: "scroll")
                .background(Color(.systemBackground))
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                
                // Sticky compact header (appears when scrolled past collapse point)
                if scrollOffset < -250 {
                    VStack {
                        StickyCompactHeader(
                            podcast: podcast,
                            onDismiss: { dismiss() },
                            onShowAbout: { showingDescriptionSheet = true },
                            filterOption: filterOption,
                            sortOrder: sortOrder,
                            onFilterChange: { filterOption = $0 },
                            onSortChange: { sortOrder = $0 },
                            isSubscribed: appModel.podcasts.contains { $0.feedURL == podcast.feedURL },
                            isProcessingSubscription: isSubscribing,
                            onSubscribe: { Task { await subscribeToPodcast() } },
                            onUnsubscribe: { showingUnsubscribeAlert = true }
                        )
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: scrollOffset < -250)
                }
            }

            .overlay(alignment: .top) {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                    .offset(y: 30) 
                    
                    Spacer()
                    
                    Menu {
                        // Filter options
                        Menu("Filter Episodes") {
                            Button(action: { filterOption = .all }) {
                                Label("All Episodes", systemImage: filterOption == .all ? "checkmark" : "")
                            }
                            Button(action: { filterOption = .unplayed }) {
                                Label("Unplayed", systemImage: filterOption == .unplayed ? "checkmark" : "")
                            }
                            Button(action: { filterOption = .played }) {
                                Label("Played", systemImage: filterOption == .played ? "checkmark" : "")
                            }
                        }
                        
                        // Sort options
                        Menu("Sort Episodes") {
                            Button(action: { sortOrder = .newestFirst }) {
                                Label("Newest First", systemImage: sortOrder == .newestFirst ? "checkmark" : "")
                            }
                            Button(action: { sortOrder = .oldestFirst }) {
                                Label("Oldest First", systemImage: sortOrder == .oldestFirst ? "checkmark" : "")
                            }
                        }

                        // Subscribe/Unsubscribe option
                        let isSubscribed = appModel.podcasts.contains { $0.feedURL == podcast.feedURL }
                        let isProcessing = isSubscribing
                        
                        if isSubscribed {
                            Button(action: { showingUnsubscribeAlert = true }) {
                                Label("Unsubscribe", systemImage: "minus.circle")
                            }
                            .disabled(isProcessing)
                        } else {
                            Button(action: { Task { await subscribeToPodcast() } }) {
                                Label(isProcessing ? "Subscribing..." : "Subscribe", systemImage: "plus.circle")
                            }
                            .disabled(isProcessing)
                        }
                        
                        // "About" button
                        if !podcast.description.isEmpty {
                            Button(action: { showingDescriptionSheet = true }) {
                                Label("About", systemImage: "info.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                    }
                    .offset(y: 30) 
                }
                .padding(.horizontal, 20)
                .padding(.top, geometry.safeAreaInsets.top + 30)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: $showingDescriptionSheet) {
            PodcastDescriptionView(
                podcast: podcast,
                onDismiss: { showingDescriptionSheet = false }
            )
        }
        .alert("Unsubscribe from Podcast", isPresented: $showingUnsubscribeAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Unsubscribe", role: .destructive) {
                Task { await unsubscribeFromPodcast() }
            }
        } message: {
            Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? This will remove it from your library.")
        }
        .subscriptionErrorAlert(
            error: $subscriptionError,
            podcastTitle: podcast.title,
            onRetry: {
                Task { await subscribeToPodcast() }
            }
        )
        .background(
            NavigationLink(
                destination: selectedEpisode.map { EpisodeDetailView(episodeWithState: $0) },
                isActive: Binding(
                    get: { selectedEpisode != nil },
                    set: { if !$0 { selectedEpisode = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        )
        .onAppear {
            // Subscription state is read directly from `appModel.podcasts` above.
        }
    }
    
    // MARK: - Episodes Content
    private var episodesContent: some View {
        VStack(spacing: 0) {
            // Episodes header with filter/sort controls
            HStack {
                Text("Episodes")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Filter and sort menu
                Menu {
                    // Filter options
                    Menu("Filter Episodes") {
                        Button(action: { filterOption = .all }) {
                            Label("All Episodes", systemImage: filterOption == .all ? "checkmark" : "")
                        }
                        Button(action: { filterOption = .unplayed }) {
                            Label("Unplayed", systemImage: filterOption == .unplayed ? "checkmark" : "")
                        }
                        Button(action: { filterOption = .played }) {
                            Label("Played", systemImage: filterOption == .played ? "checkmark" : "")
                        }
                    }
                    
                    // Sort options
                    Menu("Sort Episodes") {
                        Button(action: { sortOrder = .newestFirst }) {
                            Label("Newest First", systemImage: sortOrder == .newestFirst ? "checkmark" : "")
                        }
                        Button(action: { sortOrder = .oldestFirst }) {
                            Label("Oldest First", systemImage: sortOrder == .oldestFirst ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            // Episodes list, read straight from `AppModel`'s `Store`.
            PodcastEpisodeListView(
                podcastID: podcast.id,
                podcastTitle: podcast.title,
                podcastArtworkURL: podcast.artworkURL,
                filterOption: filterOption,
                sortOrder: sortOrder,
                onEpisodeTap: { episodeWithState in
                    swipeStateManager.closeAllSwipeActions()
                    selectedEpisode = episodeWithState
                }
            )
            .clipped() // Prevent overflow
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helper Functions
    
    // MARK: - Subscription Management
    
    /// Subscribe to the current podcast
    private func subscribeToPodcast() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            _ = try await appModel.subscribe(feedURL: podcast.feedURL)
            logger.info("Successfully subscribed to \(podcast.title)")
        } catch {
            subscriptionError = .unknownError(error.localizedDescription)
            logger.error("Unexpected error subscribing to \(podcast.title): \(error)")
        }
    }

    /// Unsubscribe from the current podcast
    private func unsubscribeFromPodcast() async {
        await appModel.unsubscribe(podcast.id)
        logger.info("Successfully unsubscribed from \(podcast.title)")

        // Dismiss the view after unsubscribing
        await MainActor.run {
            self.presentationMode.wrappedValue.dismiss()
        }
    }
    
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Description Sheet View
struct PodcastDescriptionView: View {
    let podcast: Podcast
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        BulletproofAsyncImage(url: podcast.artworkURL) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .shadow(radius: 5)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(podcast.cleanTitle.isEmpty ? podcast.title : podcast.cleanTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(podcast.author)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    Text(podcast.description.cleanedDescription)
                        .font(.body)
                        .lineSpacing(5)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}


// MARK: - Preview
struct PodcastDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PodcastDetailView(podcast: Podcast(
                id: UUID(),
                title: "Sample Podcast",
                author: "Sample Author",
                description: "This is a sample podcast description that shows how the layout looks with longer text content.",
                feedURL: URL(string: "https://example.com/feed.rss")!,
                artworkURL: URL(string: "https://example.com/artwork.jpg")
            ))
        }
    }
}
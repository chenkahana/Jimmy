import SwiftUI
import TipKit

// MARK: - Cache Data Structure (kept for backward compatibility)
struct DiscoveryCacheData: Codable {
    let trending: [TrendingEpisode]
    let featured: [PodcastSearchResult]
    let charts: [PodcastSearchResult]
    let timestamp: Date
}

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoveryViewModel.shared
    @Environment(ShellStore.self) private var shell
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var discoverNamespace
    @State private var selectedDestination: DiscoverNavigationDestination?
    @State private var detailOpenToken: InteractionLatencyTracker.Token?

    var body: some View {
        ZStack {
            JimmyScreenBackground()

            VStack(spacing: 0) {
                if !shell.discoverSearchQuery.isEmpty || !viewModel.searchText.isEmpty {
                    searchResultsSection
                } else if viewModel.isLoading && !viewModel.hasAnyData {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage, !viewModel.hasAnyData {
                    // Error state with retry
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        
                        Text("Failed to Load Content")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button("Retry") {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 32) {
                            discoverIntroCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))

                            heroFeaturedSection
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                            
                            trendingSection
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity
                                ))
                            
                            chartsSection
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.hasAnyData)
                        .padding(.vertical, 20)
                        .tabBarSpacing()
                    }
                    .refreshable {
                        await viewModel.refreshData()
                    }
                }
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: Binding(
                get: { shell.discoverSearchQuery },
                set: { newValue in
                    shell.updateDiscoverSearch(query: newValue)
                    viewModel.searchText = newValue
                }
            ),
            isPresented: Binding(
                get: { shell.isDiscoverSearchFocused },
                set: { newValue in
                    shell.setDiscoverSearchFocused(newValue)
                    isSearchFieldFocused = newValue
                }
            ),
            prompt: "Search for podcasts"
        )
        .focused($isSearchFieldFocused)
        .onChange(of: shell.discoverSearchQuery) { _, newQuery in
            if viewModel.searchText != newQuery {
                viewModel.searchText = newQuery
            }
        }
        .onChange(of: shell.isDiscoverSearchFocused) { _, newValue in
            isSearchFieldFocused = newValue
        }
        .onAppear {
            if viewModel.searchText != shell.discoverSearchQuery {
                viewModel.searchText = shell.discoverSearchQuery
            }
            Task { [weak viewModel] in
                await viewModel?.loadDataIfNeeded()
            }
        }
        .alert("Subscription", isPresented: $viewModel.showingSubscriptionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.subscriptionMessage)
        }
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .podcast(let result, let sourceID):
                AsyncPodcastDetailView(searchResult: result)
                    .navigationTransition(.zoom(sourceID: sourceID, in: discoverNamespace))
                    .task {
                        finishDetailOpenMeasurement()
                    }
            case .trending(let episode, let sourceID):
                TrendingEpisodeDetailView(episode: episode)
                    .navigationTransition(.zoom(sourceID: sourceID, in: discoverNamespace))
                    .task {
                        finishDetailOpenMeasurement()
                    }
            }
        }
    }
    
    private var searchResultsSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                JimmySectionHeader(
                    eyebrow: "Search",
                    title: "Search results",
                    subtitle: viewModel.isSearching
                    ? "Searching the catalog..."
                    : "\(viewModel.searchResults.count) podcasts found",
                    icon: "magnifyingglass"
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                if viewModel.isSearching {
                    LazyVStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { index in
                            LiquidSkeletonView(style: .searchResult)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .proMotionSpring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: viewModel.isSearching
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                } else if viewModel.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No podcasts found")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Try searching with different keywords")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.searchResults) { result in
                            Button {
                                openPodcast(result, sourceID: "discover-search-\(result.id)")
                            } label: {
                                DiscoverSearchResultRow(
                                    result: result,
                                    isSubscribed: viewModel.isSubscribed(result),
                                    isProcessing: viewModel.isProcessing(result),
                                    onSubscribe: {
                                        Task {
                                            await viewModel.subscribe(to: result)
                                        }
                                    }
                                )
                                .matchedTransitionSource(id: "discover-search-\(result.id)", in: discoverNamespace)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                        }
                    }
                    .tabBarBottomPadding()
                }
            }
        }
    }

    private var discoverIntroCard: some View {
        JimmyCard(isHighlighted: true, padding: JimmyDesign.Spacing.xl) {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.lg) {
                JimmySectionHeader(
                    eyebrow: "Editorial",
                    title: "Find the next show that earns a place in your queue",
                    subtitle: "Featured picks, trending episodes, and chart leaders are all here with one search model behind them.",
                    icon: "sparkles"
                )

                HStack(spacing: JimmyDesign.Spacing.sm) {
                    discoverSignalPill(title: "Featured", icon: "star.fill")
                    discoverSignalPill(title: "Trending", icon: "flame.fill")
                    discoverSignalPill(title: "Charts", icon: "chart.line.uptrend.xyaxis")
                }
            }
        }
        .padding(.horizontal, 20)
        .popoverTip(DiscoverSearchTip(), arrowEdge: .top)
    }

    private func discoverSignalPill(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.08))
        )
    }
    
    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                // Featured section skeleton
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 120, height: 32)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 16)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(0..<3, id: \.self) { _ in
                                LiquidSkeletonView(style: .podcastCard)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                // Trending section skeleton
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 160, height: 28)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 180, height: 16)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<3, id: \.self) { _ in
                                LiquidSkeletonView(style: .libraryGrid)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                // Charts section skeleton
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 28)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 150, height: 16)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    LazyVStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { _ in
                            LiquidSkeletonView(style: .episodeRow)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
            .tabBarSpacing()
        }
    }
    
    private var heroFeaturedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Featured")
                        .font(JimmyDesign.Typography.largeTitle)
                        .foregroundStyle(.primary)
                    
                    Text("Handpicked podcasts just for you")
                        .font(JimmyDesign.Typography.body)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(viewModel.featured.prefix(5))) { podcast in
                        Button {
                            openPodcast(podcast, sourceID: "discover-featured-\(podcast.id)")
                        } label: {
                            EnhancedFeaturedPodcastCard(
                                result: podcast,
                                isSubscribed: viewModel.isSubscribed(podcast),
                                isProcessing: viewModel.isProcessing(podcast),
                                onSubscribe: {
                                    Task {
                                        await viewModel.subscribe(to: podcast)
                                    }
                                }
                            )
                            .matchedTransitionSource(id: "discover-featured-\(podcast.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .carouselScrollTransition()
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trending Episodes")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    
                    Text("What everyone's listening to")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.trending.prefix(5)), id: \.id) { (episode: TrendingEpisode) in
                        Button {
                            openTrendingEpisode(episode, sourceID: "discover-trending-\(episode.id)")
                        } label: {
                            EnhancedTrendingEpisodeCard(
                                episode: episode,
                                onSubscribe: {
                                    // For trending episodes, we need to create a PodcastSearchResult from the episode
                                    let podcastResult = PodcastSearchResult(
                                        id: episode.id,
                                        title: episode.podcastName,
                                        author: episode.podcastName,
                                        feedURL: episode.feedURL,
                                        artworkURL: episode.artworkURL,
                                        description: nil,
                                        genre: "Podcast",
                                        trackCount: 1
                                    )
                                    Task {
                                        await viewModel.subscribe(to: podcastResult)
                                    }
                                }
                            )
                            .matchedTransitionSource(id: "discover-trending-\(episode.id)", in: discoverNamespace)
                        }
                        .buttonStyle(.plain)
                        .carouselScrollTransition()
                        .trendingEpisodeContextMenu(
                            episode: episode,
                            onSubscribe: {
                                let podcastResult = PodcastSearchResult(
                                    id: episode.id,
                                    title: episode.podcastName,
                                    author: episode.podcastName,
                                    feedURL: episode.feedURL,
                                    artworkURL: episode.artworkURL,
                                    description: nil,
                                    genre: "Podcast",
                                    trackCount: 1
                                )
                                Task {
                                    await viewModel.subscribe(to: podcastResult)
                                }
                            },
                            onShare: {
                                shareEpisode(episode)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
 
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Charts")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    
                    Text("Most popular podcasts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 20)
            
            LazyVStack(spacing: 12) {
                ForEach(Array(viewModel.charts.enumerated()), id: \.element.id) { index, result in
                    Button {
                        openPodcast(result, sourceID: "discover-charts-\(result.id)")
                    } label: {
                        EnhancedTopChartRow(
                            index: index + 1,
                            result: result,
                            isSubscribed: viewModel.isSubscribed(result),
                            onSubscribe: { 
                                Task {
                                    await viewModel.subscribe(to: result)
                                }
                            }
                        )
                        .matchedTransitionSource(id: "discover-charts-\(result.id)", in: discoverNamespace)
                    }
                    .buttonStyle(.plain)
                    .staggeredAppear(index: index)
                    .scrollEdgeTransition()
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    DiscoverView()
        .environment(ShellStore.shared)
}

// MARK: - DiscoverView Extension

extension DiscoverView {
    private func shareEpisode(_ episode: TrendingEpisode) {
        // Share functionality will be handled by the context menu modifier
        // For trending episodes, we can share the podcast link
    }

    private func openPodcast(_ result: PodcastSearchResult, sourceID: String) {
        detailOpenToken = InteractionLatencyTracker.shared.begin(.podcastDetailOpen, detail: result.title)
        selectedDestination = .podcast(result: result, sourceID: sourceID)
    }

    private func openTrendingEpisode(_ episode: TrendingEpisode, sourceID: String) {
        detailOpenToken = InteractionLatencyTracker.shared.begin(.podcastDetailOpen, detail: episode.title)
        selectedDestination = .trending(episode: episode, sourceID: sourceID)
    }

    private func finishDetailOpenMeasurement() {
        guard let detailOpenToken else {
            return
        }

        InteractionLatencyTracker.shared.end(detailOpenToken)
        self.detailOpenToken = nil
    }
}

private enum DiscoverNavigationDestination: Identifiable, Hashable {
    case podcast(result: PodcastSearchResult, sourceID: String)
    case trending(episode: TrendingEpisode, sourceID: String)

    var id: String {
        switch self {
        case .podcast(let result, let sourceID):
            return "podcast-\(result.id)-\(sourceID)"
        case .trending(let episode, let sourceID):
            return "trending-\(episode.id)-\(sourceID)"
        }
    }

    static func == (lhs: DiscoverNavigationDestination, rhs: DiscoverNavigationDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

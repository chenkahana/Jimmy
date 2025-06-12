import SwiftUI

// MARK: - Cache Data Structure (kept for backward compatibility)
struct DiscoveryCacheData: Codable {
    let trending: [TrendingEpisode]
    let featured: [PodcastSearchResult]
    let charts: [PodcastSearchResult]
    let timestamp: Date
}
    


struct DiscoverView: View {
    @StateObject private var viewModel = DiscoveryViewModel.shared

    var body: some View {
        NavigationView {
            ZStack {
            // Clean solid background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if !viewModel.searchText.isEmpty {
                searchResultsSection
            } else if viewModel.isLoading && !viewModel.hasAnyData {
                loadingView
            } else {
                ScrollView {
                    LazyVStack(spacing: 32) {
                        heroFeaturedSection
                        trendingSection
                        chartsSection
                    }
                    .padding(.vertical, 20)
                }
                .refreshable {
                    await viewModel.refreshData()
                }
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search for podcasts")
        .onChange(of: viewModel.searchText) { _ in
            Task { [weak viewModel] in
                await viewModel?.searchPodcasts()
            }
        }
        .onAppear {
            Task { [weak viewModel] in
                await viewModel?.loadDataIfNeeded()
            }
        }
        .alert("Subscription", isPresented: $viewModel.showingSubscriptionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.subscriptionMessage)
        }
        }
    }
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Results")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    
                    if viewModel.isSearching {
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(viewModel.searchResults.count) podcasts found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 20)
            
            if viewModel.isSearching {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.accentColor)
                    
                    Text("Searching for podcasts...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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
                        NavigationLink(destination: PodcastDetailView(podcast: result.toPodcast())) {
                            DiscoverSearchResultRow(
                                result: result,
                                isSubscribed: viewModel.isSubscribed(result),
                                onSubscribe: {
                                    Task {
                                        await viewModel.subscribe(to: result)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.accentColor)
            
            Text("Discovering amazing podcasts...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
    
    private var heroFeaturedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Featured")
                        .font(.largeTitle.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Handpicked podcasts just for you")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(viewModel.featured.prefix(5))) { podcast in
                        NavigationLink(destination: PodcastDetailView(podcast: podcast.toPodcast())) {
                            EnhancedFeaturedPodcastCard(
                                result: podcast,
                                isSubscribed: viewModel.isSubscribed(podcast),
                                onSubscribe: { 
                                    Task {
                                        await viewModel.subscribe(to: podcast)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.2), value: false)
                    }
                }
                .padding(.horizontal, 20)
            }
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
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(viewModel.trending.prefix(5)), id: \.id) { (episode: TrendingEpisode) in
                        NavigationLink(destination: TrendingEpisodeDetailView(episode: episode)) {
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
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.15), value: false)
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
                    NavigationLink(destination: PodcastDetailView(podcast: result.toPodcast())) {
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
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 0.18), value: false)
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    DiscoverView()
}

// MARK: - Enhanced Card Components

struct EnhancedFeaturedPodcastCard: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    
    private static let colorPairs: [(Color, Color)] = [
        (.pink, .orange),
        (.purple, .blue),
        (.green, .teal),
        (.yellow, .orange),
        (.mint, .green),
        (.cyan, .indigo),
        (.red, .pink),
        (.orange, .pink)
    ]
    
    private var gradient: LinearGradient {
        let pair = Self.colorPairs[abs(result.id) % Self.colorPairs.count]
        return LinearGradient(
            colors: [pair.0.opacity(0.15), pair.1.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Artwork with enhanced styling
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 180,
                cornerRadius: 20
            )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(isSubscribed ? "Subscribed" : "Subscribe")
                }
                .font(.caption.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            isSubscribed 
                            ? LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                        )
                )
                .foregroundColor(isSubscribed ? .green : .accentColor)
                .overlay {
                    Capsule()
                        .stroke(
                            isSubscribed ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.5),
                            lineWidth: 1
                        )
                }
                .opacity(isSubscribed ? 0.6 : 1.0)
                .onTapGesture {
                    if !isSubscribed {
                        onSubscribe()
                    }
                }
            }
        }
        .frame(width: 180)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .opacity(0.8)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.clear,
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

struct EnhancedTrendingEpisodeCard: View {
    let episode: TrendingEpisode
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artwork with trending badge
            ZStack(alignment: .topTrailing) {
                PodcastArtworkView(
                    artworkURL: episode.artworkURL,
                    size: 160,
                    cornerRadius: 16
                )
                
                // Trending badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text("HOT")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
                .shadow(color: .orange.opacity(0.6), radius: 6, x: 0, y: 3)
                .offset(x: -8, y: 8)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 160)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thinMaterial)
                .opacity(0.85)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

struct EnhancedTopChartRow: View {
    let index: Int
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Ranking number with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Text("\(index)")
                    .font(.headline.bold())
                    .foregroundColor(.accentColor)
            }
            
            // Artwork
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 70,
                cornerRadius: 12
            )
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Subscribe button
            HStack(spacing: 4) {
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(isSubscribed ? "✓" : "+")
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        isSubscribed 
                        ? LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .foregroundColor(isSubscribed ? .green : .accentColor)
            .overlay {
                Capsule()
                    .stroke(
                        isSubscribed ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.5),
                        lineWidth: 1
                    )
            }
            .opacity(isSubscribed ? 0.6 : 1.0)
            .onTapGesture {
                if !isSubscribed {
                    onSubscribe()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .opacity(0.75)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.clear,
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Search Result Components

struct DiscoverSearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Podcast artwork
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 70,
                cornerRadius: 12
            )
            
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(result.title)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                
                // Author
                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Genre badge
                HStack {
                    Text(result.genre)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    // Subscribe button
                    HStack(spacing: 4) {
                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                            .font(.caption)
                        Text(isSubscribed ? "Subscribed" : "Subscribe")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        (isSubscribed ? Color.green : Color.blue).opacity(0.2)
                    )
                    .foregroundColor(isSubscribed ? .green : .blue)
                    .cornerRadius(8)
                    .opacity(isSubscribed ? 0.6 : 1.0)
                    .onTapGesture {
                        if !isSubscribed {
                            onSubscribe()
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thickMaterial)
                .opacity(0.7)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 0.5)

    }
}

// MARK: - Detail Views

struct TrendingEpisodeDetailView: View {
    let episode: TrendingEpisode
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Large artwork
                PodcastArtworkView(
                    artworkURL: episode.artworkURL,
                    size: 300,
                    cornerRadius: 24
                )
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(episode.podcastName)
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button("Play Episode") {
                            // TODO: Implement play functionality
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Subscribe to Podcast") {
                            // TODO: Implement subscribe functionality
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground),
                    Color(.systemBackground).opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}


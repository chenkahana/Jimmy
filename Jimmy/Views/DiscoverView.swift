import SwiftUI

// MARK: - Cache Data Structure (kept for backward compatibility)
struct DiscoveryCacheData: Codable {
    let trending: [TrendingEpisode]
    let featured: [PodcastSearchResult]
    let charts: [PodcastSearchResult]
    let timestamp: Date
}
    


struct DiscoverView: View {
    @StateObject private var controller = UnifiedDiscoveryController.shared

    var body: some View {
        ZStack {
            // Beautiful gradient background
            LinearGradient(
                colors: [
                    Color("DarkBackground"),
                    Color("SurfaceElevated").opacity(0.3),
                    Color("DarkBackground")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if !controller.searchText.isEmpty {
                searchResultsSection
            } else if controller.isLoading && !controller.hasAnyData {
                loadingView
            } else {
                ScrollView {
                    LazyVStack(spacing: 32) {
                        // Cache status indicator
                        if controller.isDataCached {
                            cacheStatusView
                        }
                        
                        heroFeaturedSection
                        trendingSection
                        chartsSection
                    }
                    .padding(.vertical, 20)
                }
                .refreshable {
                    await controller.refreshData()
                }
            }
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $controller.searchText, prompt: "Search for podcasts")
        .onAppear {
            Task {
                await controller.loadDataIfNeeded()
            }
        }
        .alert("Subscription", isPresented: $controller.showingSubscriptionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(controller.subscriptionMessage)
        }
    }
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Results")
                        .font(.title.bold())
                        .foregroundColor(.primary)
                    
                    if controller.isSearching {
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(controller.searchResults.count) podcasts found")
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
            
            if controller.isSearching {
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
            } else if controller.searchResults.isEmpty {
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
                    ForEach(controller.searchResults) { result in
                        NavigationLink(destination: SearchResultDetailView(result: result)) {
                            SearchResultRow(
                                result: result,
                                isSubscribed: controller.isSubscribed(result)
                            ) {
                                // Navigation handled by NavigationLink
                            } onSubscribe: {
                                Task {
                                    await controller.subscribe(to: result)
                                }
                            }
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
                    ForEach(controller.featured.prefix(5)) { podcast in
                        EnhancedFeaturedPodcastCard(
                            result: podcast,
                            isSubscribed: controller.isSubscribed(podcast),
                            onSubscribe: { 
                                Task {
                                    await controller.subscribe(to: podcast)
                                }
                            }
                        )
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
                    ForEach(controller.trending) { episode in
                        EnhancedTrendingEpisodeCard(
                            episode: episode,
                            onSubscribe: {}
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
                ForEach(Array(controller.charts.enumerated()), id: \.element.id) { index, result in
                    EnhancedTopChartRow(
                        index: index + 1,
                        result: result,
                        isSubscribed: controller.isSubscribed(result),
                        onSubscribe: { 
                            Task {
                                await controller.subscribe(to: result)
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var cacheStatusView: some View {
        HStack {
            Image(systemName: controller.isDataFresh ? "checkmark.circle.fill" : "clock.fill")
                .foregroundColor(controller.isDataFresh ? .green : .orange)
            
            Text(controller.getCacheStatusText())
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if controller.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 20)
    }
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
            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear,
                                Color.black.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            
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
                
                Button(action: onSubscribe) {
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
                                ? LinearGradient(colors: [.green.opacity(0.2), .green.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                            )
                    )
                    .foregroundColor(isSubscribed ? .green : .accentColor)
                    .overlay {
                        Capsule()
                            .stroke(
                                isSubscribed ? Color.green.opacity(0.3) : Color.accentColor.opacity(0.3),
                                lineWidth: 1
                            )
                    }
                }
                .disabled(isSubscribed)
            }
        }
        .frame(width: 180)
        .padding(20)
        .background(gradient)
        .enhanced3DCard(cornerRadius: 24, elevation: 4)
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
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                
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
                .shadow(color: .orange.opacity(0.5), radius: 4, x: 0, y: 2)
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
            LinearGradient(
                colors: [
                    Color("SurfaceElevated"),
                    Color("SurfaceElevated").opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .enhanced3DCard(cornerRadius: 20, elevation: 3)
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
                            colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.1)],
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
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            
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
            Button(action: onSubscribe) {
                HStack(spacing: 4) {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                    Text(isSubscribed ? "✓" : "Add")
                }
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            isSubscribed 
                            ? Color.green.opacity(0.15)
                            : Color.accentColor.opacity(0.15)
                        )
                )
                .foregroundColor(isSubscribed ? .green : .accentColor)
                .overlay {
                    Capsule()
                        .stroke(
                            isSubscribed ? Color.green.opacity(0.3) : Color.accentColor.opacity(0.3),
                            lineWidth: 1
                        )
                }
            }
            .disabled(isSubscribed)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color("SurfaceElevated"),
                            Color("SurfaceElevated").opacity(0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color("SurfaceHighlighted").opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    DiscoverView()
}

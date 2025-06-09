import SwiftUI

struct DiscoverView: View {
    @State private var trending: [TrendingEpisode] = []
    @State private var featured: [PodcastSearchResult] = []
    @State private var charts: [PodcastSearchResult] = []
    @State private var isLoading = true
    @State private var subscribed: [Podcast] = []
    @State private var showingSubscriptionAlert = false
    @State private var subscriptionMessage = ""
    @State private var searchText = ""
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var lastSearchText = ""

    var body: some View {
        Group {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if isSearching {
                    VStack {
                        ProgressView("Searching...")
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else {
                    List {
                        Section("Search Results") {
                            ForEach(searchResults) { result in
                                NavigationLink(destination: SearchResultDetailView(result: result)) {
                                    SearchResultRow(
                                        result: result,
                                        isSubscribed: isSubscribed(result)
                                    ) {
                                        // Navigation handled by NavigationLink
                                    } onSubscribe: {
                                        subscribe(to: result)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if searchResults.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No results")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else {
                ScrollView {
                    if isLoading {
                        ProgressView("Loading…")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            if !trending.isEmpty {
                                Text("Trending Episodes")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(trending) { episode in
                                            TrendingEpisodeItemView(episode: episode) {
                                                let result = PodcastSearchResult(
                                                    id: episode.id,
                                                    title: episode.podcastName,
                                                    author: "",
                                                    feedURL: episode.feedURL,
                                                    artworkURL: episode.artworkURL,
                                                    description: nil,
                                                    genre: "",
                                                    trackCount: 0
                                                )
                                                subscribe(to: result)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }

                            if !featured.isEmpty {
                                Text("Featured")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(featured) { result in
                                            NavigationLink(destination: SearchResultDetailView(result: result)) {
                                                LargeRecommendedPodcastItem(
                                                    result: result,
                                                    isSubscribed: isSubscribed(result),
                                                    onSubscribe: { subscribe(to: result) }
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }

                            if !charts.isEmpty {
                                Text("Top 100")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(charts.enumerated()), id: \.(0)) { index, result in
                                        TopChartRowView(index: index + 1, result: result, isSubscribed: isSubscribed(result)) {
                                            subscribe(to: result)
                                        }
                                    }
                                }
                                .padding(.vertical)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Discover")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Podcasts")
        .onChange(of: searchText) { oldValue, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                searchResults = []
                isSearching = false
            } else if trimmed != lastSearchText {
                lastSearchText = trimmed
                performSearch(query: trimmed)
            }
        }
        .onAppear {
            loadData()
        }
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
        }
        .background(
            RadialGradient(
                gradient: Gradient(colors: [Color.accentColor.opacity(0.05), Color(.systemBackground)]),
                center: .topLeading,
                startRadius: 100,
                endRadius: 500
            )
            .ignoresSafeArea()
        )
    }

    private func loadData() {
        guard isLoading else { return }
        subscribed = PodcastService.shared.loadPodcasts()

        let group = DispatchGroup()

        group.enter()
        DiscoveryService.shared.fetchTrendingEpisodes { eps in
            trending = eps
            group.leave()
        }

        group.enter()
        DiscoveryService.shared.fetchFeaturedPodcasts { pods in
            featured = pods
            group.leave()
        }

        group.enter()
        DiscoveryService.shared.fetchTopCharts { pods in
            charts = pods
            group.leave()
        }

        group.notify(queue: .main) {
            isLoading = false
        }
    }

    private func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        subscribed.contains { $0.feedURL == result.feedURL }
    }

    private func subscribe(to result: PodcastSearchResult) {
        if isSubscribed(result) {
            subscriptionMessage = "You're already subscribed to \(result.title)"
            showingSubscriptionAlert = true
            return
        }

        subscribed.append(result.toPodcast())
        PodcastService.shared.savePodcasts(subscribed)
        subscriptionMessage = "Successfully subscribed to \(result.title)"
        showingSubscriptionAlert = true
    }

    private func performSearch(query: String) {
        isSearching = true
        iTunesSearchService.shared.searchPodcasts(query: query) { results in
            searchResults = results
            isSearching = false
        }
    }
}

#Preview {
    NavigationView {
        DiscoverView()
    }
}

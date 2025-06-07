import SwiftUI

struct DiscoverView: View {
    @State private var recommended: [PodcastSearchResult] = []
    @State private var isLoading = true
    @State private var subscribed: [Podcast] = []
    @State private var showingSubscriptionAlert = false
    @State private var subscriptionMessage = ""
    @State private var searchText = ""
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var lastSearchText = ""

    private var groupedRecommended: [String: [PodcastSearchResult]] {
        Dictionary(grouping: recommended, by: { $0.genre })
    }

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
                        ProgressView("Loading recommendations...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 40)
                    } else if recommended.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("No recommendations yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            ForEach(groupedRecommended.keys.sorted(), id: \.self) { genre in
                                if let items = groupedRecommended[genre] {
                                    DiscoverGenreSectionView(
                                        genre: genre,
                                        results: items,
                                        isSubscribed: isSubscribed,
                                        onSubscribe: { subscribe(to: $0) }
                                    )
                                }
                            }
                        }
                        .padding(.vertical)
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
        subscribed = PodcastService.shared.loadPodcasts()
        isLoading = true
        RecommendationService.shared.getRecommendations(basedOn: subscribed) { results in
            recommended = results
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

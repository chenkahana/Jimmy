import SwiftUI
import Foundation
import Combine

struct PodcastSearchView: View {
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var localPodcasts: [Podcast] = []
    @State private var selectedSearchResult: PodcastSearchResult?
    @State private var selectedLocalPodcast: Podcast?
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = false
    @State private var selectedEpisode: Episode?
    @State private var searchScope: SearchScope = .all
    @State private var showingSubscriptionAlert = false
    @State private var subscriptionMessage = ""
    
    private let debounceTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var lastSearchText = ""
    
    enum SearchScope: String, CaseIterable {
        case all = "All"
        case subscribed = "Subscribed"
        case web = "Discover"
        
        var icon: String {
            switch self {
            case .all: return "magnifyingglass"
            case .subscribed: return "heart.fill"
            case .web: return "globe"
            }
        }
    }
    
    var filteredLocalPodcasts: [Podcast] {
        if searchText.isEmpty {
            return localPodcasts
        } else {
            return localPodcasts.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.author.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Header
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        
                        TextField("Search podcasts...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onReceive(debounceTimer) { _ in
                                if searchText != lastSearchText {
                                    lastSearchText = searchText
                                    performSearch()
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Search Scope Picker
                    Picker("Search Scope", selection: $searchScope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Label(scope.rawValue, systemImage: scope.icon)
                                .tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color(.systemBackground))
                
                // Search Results
                if isSearching {
                    VStack {
                        ProgressView("Searching...")
                        Text("Finding podcasts on Apple Podcasts...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if searchScope == .all || searchScope == .subscribed {
                            if !filteredLocalPodcasts.isEmpty {
                                Section("Your Subscriptions") {
                                    ForEach(filteredLocalPodcasts) { podcast in
                                        LocalPodcastRow(podcast: podcast) {
                                            selectedLocalPodcast = podcast
                                            loadEpisodes(for: podcast)
                                        }
                                    }
                                }
                            }
                        }
                        
                        if (searchScope == .all || searchScope == .web) && !searchResults.isEmpty {
                            Section("Discover New Podcasts") {
                                ForEach(searchResults) { result in
                                    SearchResultRow(
                                        result: result,
                                        isSubscribed: isSubscribed(result)
                                    ) {
                                        selectedSearchResult = result
                                        loadEpisodes(for: result)
                                    } onSubscribe: {
                                        subscribe(to: result)
                                    }
                                }
                            }
                        }
                        
                        if searchText.isEmpty && searchResults.isEmpty && localPodcasts.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text("Search for Podcasts")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("Find your favorite shows from Apple Podcasts or search through your subscriptions")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .refreshable {
                        await refreshData()
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadLocalPodcasts()
            }
            .sheet(item: $selectedLocalPodcast) { podcast in
                EpisodeListView(
                    podcast: podcast,
                    episodes: episodes,
                    isLoading: isLoadingEpisodes,
                    onEpisodeTap: { episode in
                        selectedEpisode = episode
                    }
                )
            }
            .sheet(item: $selectedSearchResult) { result in
                SearchResultDetailView(
                    result: result,
                    episodes: episodes,
                    isLoading: isLoadingEpisodes,
                    isSubscribed: isSubscribed(result),
                    onEpisodeTap: { episode in
                        selectedEpisode = episode
                    },
                    onSubscribe: {
                        subscribe(to: result)
                    }
                )
            }
            .sheet(item: $selectedEpisode) { episode in
                EpisodePlayerView(episode: episode)
            }
            .alert("Subscription", isPresented: $showingSubscriptionAlert) {
                Button("OK") { }
            } message: {
                Text(subscriptionMessage)
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        if searchScope == .subscribed {
            // Local search only
            return
        }
        
        isSearching = true
        
        iTunesSearchService.shared.searchPodcasts(query: searchText) { results in
            DispatchQueue.main.async {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    private func loadLocalPodcasts() {
        localPodcasts = PodcastService.shared.loadPodcasts()
    }
    
    private func loadEpisodes(for podcast: Podcast) {
        isLoadingEpisodes = true
        PodcastService.shared.fetchEpisodes(for: podcast) { eps in
            DispatchQueue.main.async {
                episodes = eps
                isLoadingEpisodes = false
            }
        }
    }
    
    private func loadEpisodes(for result: PodcastSearchResult) {
        isLoadingEpisodes = true
        let podcast = result.toPodcast()
        PodcastService.shared.fetchEpisodes(for: podcast) { eps in
            DispatchQueue.main.async {
                episodes = eps
                isLoadingEpisodes = false
            }
        }
    }
    
    private func isSubscribed(_ result: PodcastSearchResult) -> Bool {
        return localPodcasts.contains { $0.feedURL == result.feedURL }
    }
    
    private func subscribe(to result: PodcastSearchResult) {
        let podcast = result.toPodcast()
        
        // Check if already subscribed
        if isSubscribed(result) {
            subscriptionMessage = "You're already subscribed to \(result.title)"
            showingSubscriptionAlert = true
            return
        }
        
        // Add to subscriptions
        var podcasts = localPodcasts
        podcasts.append(podcast)
        localPodcasts = podcasts
        PodcastService.shared.savePodcasts(podcasts)
        
        subscriptionMessage = "Successfully subscribed to \(result.title)"
        showingSubscriptionAlert = true
    }
    
    @MainActor
    private func refreshData() async {
        loadLocalPodcasts()
        if !searchText.isEmpty {
            performSearch()
        }
    }
}

// MARK: - Supporting Views

struct LocalPodcastRow: View {
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "waveform.circle")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(podcast.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Subscribed")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct SearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onTap: () -> Void
    let onSubscribe: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: result.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "waveform.circle")
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(result.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(result.genre)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(action: onSubscribe) {
                    if isSubscribed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SearchResultDetailView: View {
    let result: PodcastSearchResult
    let episodes: [Episode]
    let isLoading: Bool
    let isSubscribed: Bool
    let onEpisodeTap: (Episode) -> Void
    let onSubscribe: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Podcast Header
                HStack(alignment: .top, spacing: 16) {
                    AsyncImage(url: result.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "waveform.circle")
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 120, height: 120)
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(result.author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(result.genre)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        
                        Button(action: onSubscribe) {
                            Label(
                                isSubscribed ? "Subscribed" : "Subscribe",
                                systemImage: isSubscribed ? "checkmark.circle.fill" : "plus.circle"
                            )
                            .foregroundColor(isSubscribed ? .green : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSubscribed ? Color.green.opacity(0.1) : Color.blue)
                            .cornerRadius(8)
                        }
                        .disabled(isSubscribed)
                    }
                    
                    Spacer()
                }
                .padding()
                
                if let description = result.description {
                    Text(description)
                        .font(.body)
                        .padding(.horizontal)
                }
                
                // Episodes List
                if isLoading {
                    VStack {
                        ProgressView("Loading episodes...")
                        Text("Fetching latest episodes...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(episodes.prefix(10)) { episode in
                        Button(action: { onEpisodeTap(episode) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                if let date = episode.publishedDate {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let desc = episode.description {
                                    Text(desc)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Podcast Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
} 
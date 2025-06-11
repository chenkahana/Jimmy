import SwiftUI
import Foundation
import Combine

struct PodcastSearchView: View {
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isSearching = false
    @State private var localPodcasts: [Podcast] = []
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
                                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                        LocalPodcastRow(podcast: podcast) {
                                            // Navigation handled by NavigationLink
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    if (searchScope == .all || searchScope == .web) && !searchResults.isEmpty {
                        Section("Discover New Podcasts") {
                            ForEach(searchResults) { result in
                                NavigationLink(destination: PodcastDetailView(podcast: result.toPodcast())) {
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
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadLocalPodcasts()
        }
        .keyboardDismissToolbar()
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
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
            // CRITICAL FIX: Use asyncAfter to prevent "Publishing changes from within view updates"
            DispatchQueue.main.async {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    private func loadLocalPodcasts() {
        localPodcasts = PodcastService.shared.loadPodcasts()
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
                PodcastArtworkView(
                    artworkURL: podcast.artworkURL,
                    size: 60,
                    cornerRadius: 8
                )
                
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
            colors: [pair.0.opacity(0.1), pair.1.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                PodcastArtworkView(
                    artworkURL: result.artworkURL,
                    size: 60,
                    cornerRadius: 8
                )
                
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
            .padding(8)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

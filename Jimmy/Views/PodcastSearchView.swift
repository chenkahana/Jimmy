import SwiftUI
import Foundation

struct PodcastSearchView: View {
    @StateObject private var viewModel = PodcastSearchViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            VStack(spacing: 12) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search podcasts...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                            viewModel.searchResults = []
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
                Picker("Search Scope", selection: $viewModel.searchScope) {
                    ForEach(PodcastSearchViewModel.SearchScope.allCases, id: \.self) { scope in
                        Label(scope.rawValue, systemImage: scope.icon)
                            .tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Search Results
            if viewModel.isSearching {
                VStack {
                    ProgressView("Searching...")
                    Text("Finding podcasts on Apple Podcasts...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if viewModel.searchScope == .all || viewModel.searchScope == .subscribed {
                        if !viewModel.localPodcasts.isEmpty {
                            Section("Your Subscriptions") {
                                ForEach(viewModel.localPodcasts) { podcast in
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
                    
                    if (viewModel.searchScope == .all || viewModel.searchScope == .web) && !viewModel.searchResults.isEmpty {
                        Section("Discover New Podcasts") {
                            ForEach(viewModel.searchResults) { result in
                                NavigationLink(destination: PodcastDetailView(podcast: result.toPodcast())) {
                                    SearchResultRow(
                                        result: result,
                                        isSubscribed: viewModel.isSubscribed(result)
                                    ) {
                                        // Navigation handled by NavigationLink
                                    } onSubscribe: {
                                        viewModel.subscribe(to: result)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if viewModel.searchText.isEmpty && viewModel.searchResults.isEmpty && viewModel.localPodcasts.isEmpty {
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
            viewModel.loadLocalPodcasts()
        }
        .keyboardDismissToolbar()
        .alert("Subscription", isPresented: $viewModel.showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(viewModel.subscriptionMessage)
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

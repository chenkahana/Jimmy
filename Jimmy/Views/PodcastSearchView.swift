import SwiftUI
import Foundation

struct PodcastSearchView: View {
    @StateObject private var viewModel = PodcastSearchViewModel()
    @State private var subscribedPodcasts: [Podcast] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header - Fixed at top as a separate block
            VStack(spacing: 12) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search podcasts or paste RSS URL...", text: $viewModel.searchText)
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
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            
            // Search Results - Completely separate section below
            if viewModel.isSearching {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Search message
                        VStack(spacing: 8) {
                            Text("Searching...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(viewModel.searchText.hasPrefix("http") ? "Importing podcast from URL..." : "Finding podcasts on Apple Podcasts...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Skeleton search results
                        LazyVStack(spacing: 12) {
                            ForEach(0..<6, id: \.self) { index in
                                LiquidSkeletonView(style: .searchResult)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity
                                    ))
                                    .animation(
                                        .spring(response: 0.5, dampingFraction: 0.8)
                                            .delay(Double(index) * 0.05),
                                        value: viewModel.isSearching
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .tabBarSpacing()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if viewModel.searchScope == .all || viewModel.searchScope == .subscribed {
                        if !subscribedPodcasts.isEmpty {
                            Section("Your Subscriptions") {
                                ForEach(subscribedPodcasts) { podcast in
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
                                NavigationLink(destination: AsyncPodcastDetailView(searchResult: result)) {
                                    SearchResultRow(
                                        result: result,
                                        isSubscribed: viewModel.isSubscribed(result)
                                    ) {
                                        // Navigation handled by NavigationLink
                                    } onSubscribe: {
                                        Task {
                                            await viewModel.subscribe(to: result)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if viewModel.searchText.isEmpty && viewModel.searchResults.isEmpty && subscribedPodcasts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("Search for Podcasts")
                                .font(.title2)
                                .fontWeight(.medium)
                            
                            Text("Find your favorite shows from Apple Podcasts, search through your subscriptions, or paste an RSS feed URL to import directly")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                subscribedPodcasts = await viewModel.getSubscribedPodcasts()
            }
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
        (.purple, .accentColor),
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
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                Button(action: onSubscribe) {
                    if isSubscribed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.accentColor)
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

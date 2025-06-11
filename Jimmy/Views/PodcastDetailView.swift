import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    
    @State private var episodes: [Episode] = []
    @State private var selectedTab: EpisodeTab = .episodes
    @State private var isSubscribed = false
    @State private var subscriptionMessage = ""
    @State private var showingSubscriptionAlert = false
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var episodeCache = EpisodeCacheService.shared
    @EnvironmentObject private var uiUpdateService: UIUpdateService
    @Environment(\.dismiss) private var dismiss
    @State private var loadingError: String?
    @State private var isLoading = false
    
    private enum EpisodeTab: String, CaseIterable, Identifiable {
        case episodes = "Episodes"
        case about = "About"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            tabPicker
            contentView
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadEpisodes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .episodeAdded)) { notification in
            handleEpisodeAdded(notification)
        }
        .alert("Subscription", isPresented: $showingSubscriptionAlert) {
            Button("OK") { }
        } message: {
            Text(subscriptionMessage)
        }
    }
    
    private var headerView: some View {
        PodcastHeaderView(podcast: podcast)
    }
    
    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(EpisodeTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
    }
    
    private var contentView: some View {
        TabView(selection: $selectedTab) {
            episodesTabView
                .tag(EpisodeTab.episodes)
            
            aboutTabView
                .tag(EpisodeTab.about)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }
    
    private var episodesTabView: some View {
        Group {
            if isLoading && episodes.isEmpty {
                loadingView
            } else if episodes.isEmpty {
                emptyStateView
            } else {
                episodesList
            }
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading episodes...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack {
            Text("No episodes available")
                .foregroundColor(.secondary)
            if let error = loadingError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var episodesList: some View {
        List(episodes) { episode in
            EpisodeRowView(
                episode: episode,
                podcast: podcast,
                isCurrentlyPlaying: audioPlayer.currentEpisode?.id == episode.id,
                onTap: {
                    audioPlayer.loadEpisode(episode)
                }
            )
        }
    }
    
    private var aboutTabView: some View {
        PodcastAboutView(podcast: podcast)
    }
    
    private func handleEpisodeAdded(_ notification: Notification) {
        if let episode = notification.object as? Episode {
            if !episodes.contains(where: { $0.id == episode.id }) {
                episodes.append(episode)
                episodes.sort(by: { $0.publishedDate ?? Date.distantPast > $1.publishedDate ?? Date.distantPast })
            }
        }
    }
    
    private func loadEpisodes() {
        isLoading = true
        loadingError = nil
        
        episodeCache.loadEpisodesProgressively(
            for: podcast,
            forceRefresh: false,
            progressCallback: { episode in
                // Add episode if not already present
                if !episodes.contains(where: { $0.id == episode.id }) {
                    episodes.append(episode)
                    episodes.sort(by: { $0.publishedDate ?? Date.distantPast > $1.publishedDate ?? Date.distantPast })
                }
            },
            completion: { allEpisodes in
                episodes = allEpisodes
                episodes.sort(by: { $0.publishedDate ?? Date.distantPast > $1.publishedDate ?? Date.distantPast })
                isLoading = false
            }
        )
    }
    
    private func toggleSubscription() {
        // Implementation for subscription toggle
        isSubscribed.toggle()
        subscriptionMessage = isSubscribed ? "Subscribed to \(podcast.title)" : "Unsubscribed from \(podcast.title)"
        showingSubscriptionAlert = true
    }
}

// MARK: - Supporting Views

struct PodcastHeaderView: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: podcast.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
            }
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                Text(podcast.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

struct PodcastAboutView: View {
    let podcast: Podcast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
            
            Text(podcast.description)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            
            // Remove website section since it doesn't exist in Podcast model
        }
        .padding()
    }
}

#Preview {
    NavigationView {
        PodcastDetailView(podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "This is a sample podcast description that explains what the show is about.",
            feedURL: URL(string: "https://example.com")!,
            artworkURL: nil
        ))
    }
} 
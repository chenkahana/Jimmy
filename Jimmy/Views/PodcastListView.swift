import SwiftUI

struct PodcastListView: View {
    @State private var searchText: String = ""
    @State private var subscribedPodcasts: [Podcast] = []
    @State private var selectedPodcast: Podcast?
    @State private var episodes: [Episode] = []
    @State private var isLoadingEpisodes = false
    @State private var selectedEpisode: Episode?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var filteredPodcasts: [Podcast] {
        if searchText.isEmpty {
            return subscribedPodcasts
        } else {
            return subscribedPodcasts.filter { 
                $0.title.localizedCaseInsensitiveContains(searchText) || 
                $0.author.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search podcasts...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
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
                .padding(.horizontal)
                .padding(.top)
                
                // Subscribed Shows Grid
                ScrollView {
                    if filteredPodcasts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            
                            Text("No Subscriptions")
                                .font(.title2)
                                .fontWeight(.medium)
                            
                            Text("Your subscribed podcasts will appear here")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredPodcasts) { podcast in
                                PodcastGridItem(podcast: podcast) {
                                    selectedPodcast = podcast
                                    loadEpisodes(for: podcast)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadSubscribedPodcasts()
            }
            .refreshable {
                loadSubscribedPodcasts()
            }
            .sheet(item: $selectedPodcast) { podcast in
                EpisodeListView(
                    podcast: podcast,
                    episodes: episodes,
                    isLoading: isLoadingEpisodes,
                    onEpisodeTap: { episode in
                        selectedEpisode = episode
                    }
                )
            }
            .sheet(item: $selectedEpisode) { episode in
                EpisodePlayerView(episode: episode)
            }
        }
    }
    
    private func loadSubscribedPodcasts() {
        subscribedPodcasts = PodcastService.shared.loadPodcasts()
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
}

// MARK: - Supporting Views

struct PodcastGridItem: View {
    let podcast: Podcast
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                AsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [Color.orange.opacity(0.3), Color.red.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            Image(systemName: "waveform.circle")
                                .font(.title)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                Text(podcast.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 32)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PodcastListView()
} 
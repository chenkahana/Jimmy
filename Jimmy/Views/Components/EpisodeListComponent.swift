import SwiftUI

/// Reusable episode list component following the Background Data Synchronization Plan
/// Provides consistent episode display across Library, Queue, and Podcast Detail views
struct EpisodeListComponent: View {
    let episodes: [Episode]
    let podcasts: [Podcast]
    let showPodcastInfo: Bool
    let isLoading: Bool
    let onEpisodePlay: (Episode) -> Void
    let onEpisodeTogglePlayedStatus: (Episode) -> Void
    let onEpisodeAddToQueue: (Episode) -> Void
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    init(
        episodes: [Episode],
        podcasts: [Podcast] = [],
        showPodcastInfo: Bool = true,
        isLoading: Bool = false,
        onEpisodePlay: @escaping (Episode) -> Void,
        onEpisodeTogglePlayedStatus: @escaping (Episode) -> Void,
        onEpisodeAddToQueue: @escaping (Episode) -> Void
    ) {
        self.episodes = episodes
        self.podcasts = podcasts
        self.showPodcastInfo = showPodcastInfo
        self.isLoading = isLoading
        self.onEpisodePlay = onEpisodePlay
        self.onEpisodeTogglePlayedStatus = onEpisodeTogglePlayedStatus
        self.onEpisodeAddToQueue = onEpisodeAddToQueue
    }
    
    var body: some View {
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
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading Episodes...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Episodes")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text("Episodes will appear here when available")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Episodes List
    
    private var episodesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(episodes, id: \.id) { episode in
                EpisodeRowComponent(
                    episode: episode,
                    podcast: getPodcast(for: episode),
                    showPodcastInfo: showPodcastInfo,
                    isPlaying: audioPlayer.currentEpisode?.id == episode.id,
                    onPlay: { onEpisodePlay(episode) },
                    onTogglePlayedStatus: { onEpisodeTogglePlayedStatus(episode) },
                    onAddToQueue: { onEpisodeAddToQueue(episode) }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        guard let podcastID = episode.podcastID else { return nil }
        return podcasts.first { $0.id == podcastID }
    }
}

// MARK: - Episode Row Component

struct EpisodeRowComponent: View {
    let episode: Episode
    let podcast: Podcast?
    let showPodcastInfo: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onTogglePlayedStatus: () -> Void
    let onAddToQueue: () -> Void
    
    @State private var showingEpisodeDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode Artwork
            episodeArtwork
            
            // Episode Info
            episodeInfo
            
            Spacer()
            
            // Action Menu
            actionMenu
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .opacity(episode.played ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            showingEpisodeDetail = true
        }
        .sheet(isPresented: $showingEpisodeDetail) {
            if let podcast = podcast {
                EpisodeDetailView(episode: episode, podcast: podcast)
            }
        }
    }
    
    // MARK: - Episode Artwork
    
    private var episodeArtwork: some View {
        AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.gray)
                )
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            onPlay()
        }
    }
    
    // MARK: - Episode Info
    
    private var episodeInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Episode Title
            Text(episode.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundColor(episode.played ? .secondary : .primary)
            
            // Podcast Title (if showing podcast info)
            if showPodcastInfo, let podcast = podcast {
                Text(podcast.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Episode Metadata
            episodeMetadata
        }
    }
    
    private var episodeMetadata: some View {
        HStack(spacing: 8) {
            // Publication Date
            if let date = episode.publishedDate {
                Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Progress Indicator
            if episode.playbackPosition > 0 && !episode.played {
                if episode.episodeDuration > 0 {
                    let progress = episode.playbackPosition / episode.episodeDuration
                    Text("\(Int(progress * 100))% played")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(3)
                }
            } else if episode.played {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            // Currently Playing Indicator
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Action Menu
    
    private var actionMenu: some View {
        Menu {
            Button(action: onPlay) {
                Label("Play Episode", systemImage: "play.circle")
            }
            
            Button(action: onAddToQueue) {
                Label("Add to Queue", systemImage: "plus.circle")
            }
            
            Button(action: onTogglePlayedStatus) {
                Label(
                    episode.played ? "Mark as Unplayed" : "Mark as Played",
                    systemImage: episode.played ? "circle" : "checkmark.circle"
                )
            }
            
            Button(action: { showingEpisodeDetail = true }) {
                Label("Episode Details", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
    }
}

// MARK: - Preview

struct EpisodeListComponent_Previews: PreviewProvider {
    static var previews: some View {
        EpisodeListComponent(
            episodes: [],
            onEpisodePlay: { _ in },
            onEpisodeTogglePlayedStatus: { _ in },
            onEpisodeAddToQueue: { _ in }
        )
    }
} 
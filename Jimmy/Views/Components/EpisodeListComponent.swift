import SwiftUI

/// Reusable episode list component following the Background Data Synchronization Plan
/// Provides consistent episode display across Library, Queue, and Podcast Detail views
struct EpisodeListComponent: View {
    let episodes: [EpisodeWithPlaybackState]
    let podcasts: [Podcast]
    let showPodcastInfo: Bool
    let isLoading: Bool
    let onEpisodePlay: (Episode) -> Void
    let onEpisodeToggleFinished: (EpisodeWithPlaybackState) -> Void
    let onEpisodeAddToQueue: (Episode) -> Void
    
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    init(
        episodes: [EpisodeWithPlaybackState],
        podcasts: [Podcast] = [],
        showPodcastInfo: Bool = true,
        isLoading: Bool = false,
        onEpisodePlay: @escaping (Episode) -> Void,
        onEpisodeToggleFinished: @escaping (EpisodeWithPlaybackState) -> Void,
        onEpisodeAddToQueue: @escaping (Episode) -> Void
    ) {
        self.episodes = episodes
        self.podcasts = podcasts
        self.showPodcastInfo = showPodcastInfo
        self.isLoading = isLoading
        self.onEpisodePlay = onEpisodePlay
        self.onEpisodeToggleFinished = onEpisodeToggleFinished
        self.onEpisodeAddToQueue = onEpisodeAddToQueue
    }
    
    var body: some View {
        Group {
            if isLoading && episodes.isEmpty {
                ProgressView("Loading Episodes...")
            } else if episodes.isEmpty {
                Text("No Episodes")
            } else {
                episodesList
            }
        }
    }
    
    private var episodesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(episodes, id: \.id) { episodeWithState in
                EpisodeRowComponent(
                    episodeWithState: episodeWithState,
                    podcast: getPodcast(for: episodeWithState.episode),
                    showPodcastInfo: showPodcastInfo,
                    isPlaying: audioPlayer.currentEpisode?.id == episodeWithState.episode.id,
                    onPlay: { onEpisodePlay(episodeWithState.episode) },
                    onToggleFinished: { onEpisodeToggleFinished(episodeWithState) },
                    onAddToQueue: { onEpisodeAddToQueue(episodeWithState.episode) }
                )
            }
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        guard let podcastID = episode.podcastID else { return nil }
        return podcasts.first { $0.id == podcastID }
    }
}

// MARK: - Episode Row Component

struct EpisodeRowComponent: View {
    let episodeWithState: EpisodeWithPlaybackState
    let podcast: Podcast?
    let showPodcastInfo: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onToggleFinished: () -> Void
    let onAddToQueue: () -> Void
    
    @State private var showingEpisodeDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            episodeArtwork
            episodeInfo
            Spacer()
            actionMenu
        }
        .padding(.vertical, 8)
        .opacity(episodeWithState.playbackState.finished ? 0.6 : 1.0)
        .onTapGesture { showingEpisodeDetail = true }
        .episodeContextMenu(
            episode: episodeWithState.episode,
            episodeWithState: episodeWithState,
            onAddToQueue: onAddToQueue,
            onMarkAsPlayed: onToggleFinished,
            onPlayNext: { onPlayNext() },
            onShare: { shareEpisode() }
        )
        .sheet(isPresented: $showingEpisodeDetail) {
            EpisodeDetailView(episodeWithState: episodeWithState)
        }
    }
    
    private var episodeArtwork: some View {
        BulletproofAsyncImage(url: episodeWithState.episode.artworkURL ?? podcast?.artworkURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onPlay)
    }
    
    private var episodeInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(episodeWithState.episode.title)
                .font(.headline)
                .lineLimit(2)
                .foregroundColor(episodeWithState.playbackState.finished ? .secondary : .primary)
            
            if showPodcastInfo, let podcast = podcast {
                Text(podcast.title).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            
            episodeMetadata
        }
    }
    
    private var episodeMetadata: some View {
        HStack(spacing: 8) {
            if let date = episodeWithState.episode.publishedDate {
                Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                    .font(.caption).foregroundColor(.secondary)
            }
            
            if episodeWithState.playbackState.finished {
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
            }
            
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundColor(.accentColor)
            }
        }
    }
    
    private var actionMenu: some View {
        Menu {
            Button(action: onPlay) { Label("Play Episode", systemImage: "play.circle") }
            Button(action: onAddToQueue) { Label("Add to Queue", systemImage: "plus.circle") }
            Button(action: onToggleFinished) {
                Label(
                    episodeWithState.playbackState.finished ? "Mark as Unplayed" : "Mark as Played",
                    systemImage: episodeWithState.playbackState.finished ? "circle" : "checkmark.circle"
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title2).foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func onPlayNext() {
        Task {
            await AppModel.current?.playNext(episodeWithState.episode.id)
        }
    }
    
    private func shareEpisode() {
        // Share functionality will be handled by the context menu modifier
    }
}

// MARK: - Preview

struct EpisodeListComponent_Previews: PreviewProvider {
    static var previews: some View {
        EpisodeListComponent(
            episodes: [],
            onEpisodePlay: { _ in },
            onEpisodeToggleFinished: { _ in },
            onEpisodeAddToQueue: { _ in }
        )
    }
} 
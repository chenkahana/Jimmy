import SwiftUI

struct EpisodeListView: View {
    @StateObject private var viewModel: EpisodeListViewModel
    private let podcast: Podcast

    init(podcast: Podcast) {
        self.podcast = podcast
        _viewModel = StateObject(wrappedValue: EpisodeListViewModel(podcastID: podcast.id))
    }

    /// Convert EpisodeWithPlaybackState to EpisodeWithStatus for EpisodeCard
    private func convertToEpisodeWithStatus(_ episodeWithState: EpisodeWithPlaybackState) -> EpisodeWithStatus {
        let audioPlayer = AudioPlayerService.shared
        let progressCache = DIContainer.shared.progressCacheStore
        
        // PERFORMANCE FIX: Calculate play progress more efficiently
        let playProgress: Double
        
        // First check if we have cached progress
        if progressCache.hasProgress(for: episodeWithState.episode.id) {
            // Update cache with episode duration if available (non-blocking)
            if let duration = episodeWithState.episode.duration, duration > 0 {
                progressCache.updateProgressPercentage(for: episodeWithState.episode.id, duration: duration)
            }
            playProgress = progressCache.getProgressPercentage(for: episodeWithState.episode.id)
        } else {
            // Fallback to playback state position
            let position = episodeWithState.playbackState.position
            if let duration = episodeWithState.episode.duration, duration > 0 {
                playProgress = min(1.0, max(0.0, position / duration))
                // Cache this calculation for future use
                progressCache.setProgress(for: episodeWithState.episode.id, position: position, duration: duration)
            } else {
                playProgress = 0.0
            }
        }
        
        // PERFORMANCE FIX: Cache status calculations to avoid repeated lookups
        let isCurrentlyPlaying = audioPlayer.currentEpisode?.id == episodeWithState.episode.id
        let isQueued = AppModel.current?.isQueued(episodeWithState.episode.id) ?? false
        
        let status = EpisodeWithStatus.deriveStatus(
            episode: episodeWithState.episode,
            playProgress: playProgress,
            isQueued: isQueued,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
        
        return EpisodeWithStatus(
            episode: episodeWithState.episode,
            podcastTitle: podcast.title,
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcast.artworkURL
        )
    }

    var body: some View {
        List {
            ForEach(viewModel.episodes) { episodeWithState in
                let episodeWithStatus = convertToEpisodeWithStatus(episodeWithState)
                
                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        // Handle episode detail navigation if needed
                    },
                    onPlay: {
                        AudioPlayerService.shared.loadEpisode(episodeWithState.episode, startPlaying: true)
                    },
                    onAddToQueue: {
                        Task {
                            await AppModel.current?.enqueue(episodeWithState.episode.id)
                        }
                    },
                    onToggleFinished: {
                        Task {
                            await viewModel.toggleFinished(for: episodeWithState)
                        }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    if episodeWithState.id == viewModel.episodes.last?.id {
                        Task {
                            await viewModel.loadMoreEpisodes()
                        }
                    }
                }
            }
            
            if case .loading = viewModel.state {
                LazyVStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        LiquidSkeletonView(style: .episodeRow)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity
                            ))
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.05),
                                value: viewModel.state
                            )
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(podcast.title)
        .onAppear {
            Task {
                await viewModel.loadInitialEpisodes()
            }
        }
        .onReceive(DIContainer.shared.progressCacheStore.$progressPercentageMap) { _ in
            // Debounce progress updates to prevent UI stuttering
            LoadingOptimizer.shared.debounce(identifier: "progress-update-\(podcast.id)") {
                // SwiftUI will automatically re-render episode cards with new progress
            }
        }
        .onChange(of: viewModel.episodes) { episodes in
            // Optimize episode loading when new episodes are loaded
            LoadingOptimizer.shared.optimizeEpisodeLoading(episodes)
        }
        .refreshable {
            await viewModel.refreshEpisodes()
        }
        .taskLifecycle(viewModel)
        .errorBanner(errorManager: viewModel.errorManager)
    }
}

// MARK: - Preview
#Preview {
    let sampleEpisodes = [
        Episode(
            id: UUID(),
            title: "Sample Episode 1",
            podcastID: UUID(),
            publishedDate: Date(),
            duration: 3600,
            artworkURL: nil,
            description: "This is a sample episode description.",
            audioURL: nil,
            played: false,
            isNew: true,
            localFileURL: nil,
            playbackPosition: 0
        ),
        Episode(
            id: UUID(),
            title: "Sample Episode 2",
            podcastID: UUID(),
            publishedDate: Date().addingTimeInterval(-86400),
            duration: 2400,
            artworkURL: nil,
            description: "Another sample episode description.",
            audioURL: nil,
            played: true,
            isNew: false,
            localFileURL: nil,
            playbackPosition: 0
        )
    ]
    
    EpisodeListView(
        podcast: Podcast(
            id: UUID(),
            title: "Sample Podcast",
            author: "Sample Author",
            description: "A sample podcast description",
            feedURL: URL(string: "https://example.com/feed.xml")!,
            artworkURL: nil
        )
    )
} 
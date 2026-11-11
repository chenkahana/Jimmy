import SwiftUI
import Combine

/// Simple streaming episode list view that demonstrates the core solution
/// Episodes appear progressively as they're parsed from the RSS feed
/// Phase 6: Enhanced with error banners and proper task lifecycle management
struct SimpleStreamingEpisodeListView: View {
    @StateObject private var viewModel: SimpleStreamingEpisodesViewModel
    // Show with NavigationView or embed without
    var showNavigation: Bool = true
    var podcastArtworkURL: URL? = nil
    var filterOption: PodcastDetailViewModel.EpisodeFilter = .all
    var sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst
    
    // Add callback for episode selection
    var onEpisodeTap: ((EpisodeWithPlaybackState) -> Void)? = nil
    
    // Store for debugging access
    private let podcastID: UUID
    private let feedURL: URL
    
    init(
        podcastID: UUID, 
        feedURL: URL, 
        showNavigation: Bool = true, 
        podcastArtworkURL: URL? = nil, 
        filterOption: PodcastDetailViewModel.EpisodeFilter = .all, 
        sortOrder: PodcastDetailViewModel.EpisodeSortOrder = .newestFirst,
        onEpisodeTap: ((EpisodeWithPlaybackState) -> Void)? = nil
    ) {
        self.podcastID = podcastID
        self.feedURL = feedURL
        self._viewModel = StateObject(wrappedValue: SimpleStreamingEpisodesViewModel(podcastID: podcastID, feedURL: feedURL))
        self.showNavigation = showNavigation
        self.podcastArtworkURL = podcastArtworkURL
        self.filterOption = filterOption
        self.sortOrder = sortOrder
        self.onEpisodeTap = onEpisodeTap
    }
    
    var body: some View {
        Group {
            if showNavigation {
                mainContent
                    .navigationTitle("Streaming Episodes")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar { ToolbarItem(placement: .navigationBarTrailing) { toolbarButtons } }
            } else {
                mainContent
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Convert EpisodeWithPlaybackState to EpisodeWithStatus for EpisodeCard
    private func convertToEpisodeWithStatus(_ episodeWithState: EpisodeWithPlaybackState) -> EpisodeWithStatus {
        let audioPlayer = AudioPlayerService.shared
        let queueViewModel = QueueViewModel.shared
        
        // Calculate play progress
        let playProgress = episodeWithState.episode.duration != nil && episodeWithState.episode.duration! > 0 
            ? episodeWithState.episode.playbackPosition / episodeWithState.episode.duration! 
            : 0.0
        
        // Determine status using the derivation rules
        let isCurrentlyPlaying = audioPlayer.currentEpisode?.id == episodeWithState.episode.id
        let isQueued = queueViewModel.episodes.contains { $0.id == episodeWithState.episode.id }
        
        let status = EpisodeWithStatus.deriveStatus(
            episode: episodeWithState.episode,
            playProgress: playProgress,
            isQueued: isQueued,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
        
        return EpisodeWithStatus(
            episode: episodeWithState.episode,
            podcastTitle: "", // Will be filled from podcast context
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcastArtworkURL
        )
    }
    
    // Computed property for filtered episodes - always up to date with viewModel.episodes
    private var filteredEpisodes: [EpisodeWithPlaybackState] {
        var episodes = viewModel.episodes
        
        // Apply filter
        switch filterOption {
        case .all:
            break
        case .unplayed:
            episodes = episodes.filter { !$0.playbackState.finished }
        case .played:
            episodes = episodes.filter { $0.playbackState.finished }
        case .downloaded:
            // For now, show all episodes for downloaded filter
            break
        }
        
        // Apply sort
        switch sortOrder {
        case .newestFirst:
            episodes.sort { ($0.episode.publishedDate ?? Date.distantPast) > ($1.episode.publishedDate ?? Date.distantPast) }
        case .oldestFirst:
            episodes.sort { ($0.episode.publishedDate ?? Date.distantPast) < ($1.episode.publishedDate ?? Date.distantPast) }
        case .titleAZ:
            episodes.sort { $0.episode.title < $1.episode.title }
        case .titleZA:
            episodes.sort { $0.episode.title > $1.episode.title }
        }
        
        return episodes
    }
    
    // Shared list content for both List and LazyVStack
    @ViewBuilder
    private var listContent: some View {
        // Progress header
        if showNavigation && viewModel.shouldShowProgress {
            Group {
                progressView
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        
        // Episodes section
        if showNavigation {
            Section(header: Text("Episodes").foregroundColor(.primary)) {
                episodesList
            }
        } else {
            // When embedded, show episodes directly without section wrapper
            episodesList
        }
    }
    
    // Episodes list content
    @ViewBuilder
    private var episodesList: some View {
        if viewModel.isStreaming && filteredEpisodes.isEmpty {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading episodes...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else if filteredEpisodes.isEmpty && !viewModel.isStreaming {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("No Episodes Found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("This podcast may not have any episodes or there was an error loading them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let errorMessage = viewModel.errorManager.currentError?.message {
                    Text("Error: \(errorMessage)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                Button("Retry") {
                    viewModel.refresh()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
            .padding()
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(filteredEpisodes, id: \.episode.id) { episodeWithState in
                // Convert to EpisodeWithStatus for EpisodeCard
                let episodeWithStatus = convertToEpisodeWithStatus(episodeWithState)
                
                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        // Handle episode detail navigation
                        onEpisodeTap?(episodeWithState)
                    },
                    onPlay: {
                        // Handle play action - use loadEpisode with startPlaying
                        AudioPlayerService.shared.loadEpisode(episodeWithState.episode, startPlaying: true)
                    },
                    onAddToQueue: {
                        Task {
                            try? await QueueViewModel.shared.addEpisode(episodeWithState.episode)
                        }
                    },
                    onToggleFinished: {
                        Task {
                            // Get the episode with current status from database
                            if let episodeWithStatus = try? await EpisodeService.shared.getEpisodeWithStatus(episodeWithState.episode) {
                                let isCurrentlyPlayed = episodeWithStatus.status.contains(.played)
                                
                                if isCurrentlyPlayed {
                                    // Remove played status
                                    var newStatus = episodeWithStatus.status
                                    newStatus.remove(.played)
                                    EpisodeService.shared.updateEpisodeStatus(episodeWithStatus, status: newStatus)
                                } else {
                                    // Mark as played
                                    EpisodeService.shared.setEpisodePlayed(episodeWithStatus)
                                }
                            } else {
                                // Fallback: use the episode from the view
                                let isCurrentlyPlayed = episodeWithState.episode.status.contains(.played)
                                
                                if isCurrentlyPlayed {
                                    // Remove played status
                                    var newStatus = episodeWithState.episode.status
                                    newStatus.remove(.played)
                                    EpisodeService.shared.updateEpisodeStatus(episodeWithState.episode, status: newStatus)
                                } else {
                                    // Mark as played
                                    EpisodeService.shared.setEpisodePlayed(episodeWithState.episode)
                                }
                            }
                        }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.horizontal, showNavigation ? 0 : 8) // Add padding when embedded
            }
        }
    }
    
    private func updateFilteredEpisodes() {
        // No longer needed - using computed property
    }
    
    // Core content for both embedded and standalone
    private var mainContent: some View {
        return Group {
            if showNavigation {
                List {
                    listContent
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { 
                    viewModel.refresh() 
                }
            } else {
                // When embedded, use LazyVStack instead of List to avoid scroll conflicts
                LazyVStack(spacing: 8) {
                    listContent
                }
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground)) // Use system background for proper visibility
        .taskLifecycle(viewModel)
        .errorBanner(errorManager: viewModel.errorManager)
        .frame(minHeight: showNavigation ? 0 : 200) // Ensure reasonable minimum height when embedded
        .onChange(of: viewModel.isStreaming) { _ in
            if !viewModel.isStreaming && viewModel.hasEpisodes {
            }
        }
        .onAppear {
            // Force start loading if not already started
            if viewModel.episodes.isEmpty && !viewModel.isStreaming {
                viewModel.loadWithCacheThenStream()
            }
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        VStack(spacing: 8) {
            HStack {
                if viewModel.isStreaming {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Text(viewModel.streamingProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.isStreaming {
                    Button("Cancel") {
                        viewModel.cancelStreaming()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            if viewModel.isStreaming {
                ProgressView(value: Double(viewModel.episodes.count), total: 100)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Connecting to podcast feed...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Episodes will appear as they're loaded")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Episodes Found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("This podcast feed doesn't contain any episodes, or there was an error loading them.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                viewModel.refresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Toolbar Buttons
    
    private var toolbarButtons: some View {
        HStack {
            if viewModel.isStreaming {
                Button("Cancel") {
                    viewModel.cancelStreaming()
                }
                .foregroundColor(.red)
            } else {
                Button("Refresh") {
                    viewModel.refresh()
                }
            }
        }
    }
}

// MARK: - Episode Row View
// Using existing EpisodeRowView from Views directory

// MARK: - Preview

struct SimpleStreamingEpisodeListView_Previews: PreviewProvider {
    static var previews: some View {
        SimpleStreamingEpisodeListView(
            podcastID: UUID(),
            feedURL: URL(string: "https://feeds.npr.org/510289/podcast.xml")!
        )
    }
} 
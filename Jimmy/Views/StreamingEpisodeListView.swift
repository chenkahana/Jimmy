import SwiftUI

/// A SwiftUI view that displays episodes using streaming loading.
/// This solves timeout and UI blocking issues by:
/// 1. Showing episodes progressively as they're parsed (no waiting for full download)
/// 2. Providing real-time loading progress and status
/// 3. Supporting cancellation and refresh operations
/// 4. Using throttled UI updates for smooth performance
/// 5. Maintaining responsive UI during large feed processing
struct StreamingEpisodeListView: View {
    @StateObject private var viewModel: StreamingShowEpisodesViewModel
    private let podcast: Podcast
    
    init(podcast: Podcast) {
        self.podcast = podcast
        _viewModel = StateObject(wrappedValue: StreamingShowEpisodesViewModel(
            podcast: podcast
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and filter controls
                searchAndFilterSection
                
                // Main content area
                mainContentView
            }
            .navigationTitle(podcast.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    toolbarButtons
                }
            }
            .onAppear {
                // Start streaming episodes when view appears with fallback support
                if viewModel.displayedEpisodes.isEmpty && !viewModel.isStreaming {
                    viewModel.startStreamingEpisodes()
                }
            }
            .onDisappear {
                // Stop streaming when view disappears to save resources
                viewModel.stopStreaming()
            }
        }
    }
    
    // MARK: - View Components
    
    private var searchAndFilterSection: some View {
        VStack(spacing: 8) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search episodes...", text: $viewModel.searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !viewModel.searchText.isEmpty {
                    Button("Clear") {
                        viewModel.searchText = ""
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            // Sort and filter controls
            HStack {
                // Sort picker
                Picker("Sort", selection: $viewModel.sortOrder) {
                    ForEach(StreamingShowEpisodesViewModel.EpisodeSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Spacer()
                
                // Filter picker
                Picker("Filter", selection: $viewModel.filterType) {
                    ForEach(StreamingShowEpisodesViewModel.EpisodeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
            .padding(.horizontal)
            .font(.caption)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .error(let errorMessage):
            errorView(errorMessage)
        case .loaded:
            if viewModel.displayedEpisodes.isEmpty && !viewModel.isStreaming {
                emptyStateView
            } else {
                episodeListView
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            // Progress indicator
            if viewModel.streamProgress.totalEpisodes != nil {
                // Determinate progress when we know total count
                ProgressView(value: viewModel.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(maxWidth: 200)
            } else {
                // Indeterminate progress when streaming
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            // Status text
            VStack(spacing: 4) {
                Text(viewModel.loadingStatusText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                if let lastEpisode = viewModel.streamProgress.lastEpisodeTitle {
                    Text("Latest: \(lastEpisode)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Cancel button
            if viewModel.isStreaming {
                Button("Cancel") {
                    viewModel.stopStreaming()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            // Show any episodes that have already loaded
            if !viewModel.displayedEpisodes.isEmpty {
                Divider()
                    .padding(.vertical)
                
                Text("Episodes loaded so far:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Mini episode list
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.displayedEpisodes.prefix(5), id: \.episode.id) { episodeWithState in
                        let episodeWithStatus = convertToEpisodeWithStatus(episodeWithState)
                        EpisodeCard(
                            episode: episodeWithStatus,
                            onTap: {},
                            onPlay: {
                                AudioPlayerService.shared.loadEpisode(episodeWithState.episode, startPlaying: true)
                            },
                            onAddToQueue: {
                                Task {
                                    try? await QueueViewModel.shared.addEpisode(episodeWithState.episode)
                                }
                            },
                            onToggleFinished: {
                                Task {
                                    // Handle toggle finished action
                                    await toggleEpisodeFinished(episodeWithState)
                                }
                            }
                        )
                        .opacity(0.7) // Slightly faded to indicate loading state
                    }
                    
                    if viewModel.displayedEpisodes.count > 5 {
                        Text("... and \(viewModel.displayedEpisodes.count - 5) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ errorMessage: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Failed to Load Episodes")
                .font(.headline)
            
            Text(errorMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Try Again") {
                viewModel.startStreamingEpisodes()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "radio")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Episodes Found")
                .font(.headline)
            
            Text("This podcast doesn't have any episodes yet, or they couldn't be loaded.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Refresh") {
                viewModel.startStreamingEpisodes()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var episodeListView: some View {
        List {
            // Streaming progress header (if still loading)
            if viewModel.isStreaming {
                streamingProgressHeader
            }
            
            // Episode list
            ForEach(viewModel.displayedEpisodes, id: \.episode.id) { episodeWithState in
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
                            try? await QueueViewModel.shared.addEpisode(episodeWithState.episode)
                        }
                    },
                    onToggleFinished: {
                        Task {
                            await toggleEpisodeFinished(episodeWithState)
                        }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    // Check if we need to load more (for compatibility)
                    viewModel.checkForLoadMore(episode: episodeWithState)
                }
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            // Pull-to-refresh support with fallback
            viewModel.startStreamingEpisodes()
        }
    }
    
    private var streamingProgressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Loading episodes...")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(viewModel.streamProgress.progressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Stop") {
                    viewModel.stopStreaming()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            
            // Progress bar if we know total count
            if viewModel.streamProgress.totalEpisodes != nil {
                ProgressView(value: viewModel.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
    
    private var toolbarButtons: some View {
        HStack {
            // Refresh button
            Button(action: {
                viewModel.startStreamingEpisodes()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isStreaming)
            
            // Stop/Start streaming button
            if viewModel.isStreaming {
                Button(action: {
                    viewModel.stopStreaming()
                }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
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
            podcastTitle: podcast.title,
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcast.artworkURL
        )
    }
    
    /// Toggle episode finished status
    private func toggleEpisodeFinished(_ episodeWithState: EpisodeWithPlaybackState) async {
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

// MARK: - Episode Row View
// Using existing EpisodeRowView from Views directory

// MARK: - Preview

struct StreamingEpisodeListView_Previews: PreviewProvider {
    static var previews: some View {
        StreamingEpisodeListView(
            podcast: Podcast(
                id: UUID(),
                title: "Sample Podcast",
                author: "Sample Author",
                description: "A sample podcast for preview",
                feedURL: URL(string: "https://example.com/feed.xml")!,
                artworkURL: nil,
                lastEpisodeDate: Date()
            )
        )
    }
} 
import SwiftUI

/// A view that displays a paginated list of episodes for a given podcast.
/// Phase 4: Implements prefetch via SwiftUI onAppear and diffable snapshots
///
/// This view uses the `ShowEpisodesViewModel` to fetch and manage the episode data.
/// It displays a list of episodes and provides UI for loading, searching, sorting,
/// and filtering. It handles pagination automatically with prefetch as the user scrolls.
struct PaginatedEpisodeListView: View {
    @StateObject private var viewModel: ShowEpisodesViewModel
    @StateObject private var swipeStateManager = SwipeStateManager.shared
    private let podcast: Podcast
    
    // MARK: - Phase 4: Prefetch Configuration
    private let prefetchThreshold: Int = 5 // Trigger prefetch when 5 items from end

    init(podcast: Podcast) {
        self.podcast = podcast
        _viewModel = StateObject(wrappedValue: ShowEpisodesViewModel(podcastID: podcast.id, feedURL: podcast.feedURL))
    }
    
    var body: some View {
        VStack {
            switch viewModel.state {
            case .loading:
                if viewModel.displayedEpisodes.isEmpty {
                    loadingView
                } else {
                    episodeList
                }
            case .error(let errorMessage):
                errorView(errorMessage)
            case .loaded:
                if viewModel.displayedEpisodes.isEmpty {
                    emptyView
                } else {
                    episodeList
                }
            }
        }
        .navigationTitle(podcast.title)
        .task {
            // Phase 4: Load first page on appear
            await viewModel.onViewAppear()
        }
        .onDisappear {
            // Phase 4: Clean up tasks on disappear
            Task {
                await viewModel.onViewDisappear()
            }
        }
        .onReceive(DIContainer.shared.progressCacheStore.$progressPercentageMap) { _ in
            // Trigger UI refresh when progress updates
            // SwiftUI will automatically re-render episode cards with new progress
        }
        .refreshable {
            // Phase 4: Pull-to-refresh loads first page
            await viewModel.loadFirstPage()
        }
    }
    
    // MARK: - Phase 4: Episode List with Prefetch
    
    private var episodeList: some View {
        List {
            // Header with episode count and controls
            CompactEpisodeHeaderView(viewModel: viewModel)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            
            // Episode rows with prefetch
            ForEach(Array(viewModel.displayedEpisodes.enumerated()), id: \.element.id) { index, episodeWithState in
                let episodeWithStatus = convertToEpisodeWithStatus(episodeWithState)
                
                NavigationLink(destination: EpisodeDetailView(
                    episodeWithState: episodeWithState
                )) {
                    EpisodeCard(
                        episode: episodeWithStatus,
                        onTap: {
                            // Close all swipe actions when navigating
                            swipeStateManager.closeAllSwipeActions()
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
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    // Phase 4: Prefetch via SwiftUI onAppear
                    handleEpisodeAppear(at: index)
                }
            }
            
            // Loading indicator for pagination
            if viewModel.hasMorePages {
                paginationLoadingView
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Phase 4: Prefetch Logic
    
    /// Handles episode appearance for prefetch triggering
    private func handleEpisodeAppear(at index: Int) {
        let totalEpisodes = viewModel.displayedEpisodes.count
        let shouldPrefetch = index >= totalEpisodes - prefetchThreshold
        
        if shouldPrefetch && viewModel.hasMorePages {
            Task {
                await viewModel.loadNextPage()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading episodes...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            
            Text("Error Loading Episodes")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    await viewModel.loadFirstPage()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No Episodes Found")
                .font(.headline)
            
            Text("This podcast doesn't have any episodes yet, or they couldn't be loaded.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Refresh") {
                Task {
                    await viewModel.loadFirstPage()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var paginationLoadingView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading more episodes...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .listRowSeparator(.hidden)
    }
    
    /// Convert EpisodeWithPlaybackState to EpisodeWithStatus for EpisodeCard
    private func convertToEpisodeWithStatus(_ episodeWithState: EpisodeWithPlaybackState) -> EpisodeWithStatus {
        let audioPlayer = AudioPlayerService.shared
        let queueViewModel = QueueViewModel.shared
        let progressCache = DIContainer.shared.progressCacheStore
        
        // Calculate play progress - use real-time cache first, then fallback
        let playProgress: Double
        
        // CRITICAL FIX: Update progress cache with episode duration FIRST
        if episodeWithState.episode.duration != nil && episodeWithState.episode.duration! > 0 {
            progressCache.updateProgressPercentage(for: episodeWithState.episode.id, duration: episodeWithState.episode.duration!)
        }
        
        // CRITICAL FIX: Check if episode exists in cache (including 0% progress)
        // Don't use > 0 check because 0% is valid progress
        if progressCache.hasProgress(for: episodeWithState.episode.id) {
            // Episode is in cache - use cached value (could be 0% or any value)
            playProgress = progressCache.getProgressPercentage(for: episodeWithState.episode.id)
        } else {
            // Episode not in cache - fallback to episode's stored position
            playProgress = episodeWithState.episode.duration != nil && episodeWithState.episode.duration! > 0 
                ? episodeWithState.episode.playbackPosition / episodeWithState.episode.duration! 
                : 0.0
        }
        
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
            podcastTitle: "Unknown Podcast", // We don't have podcast info here
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: nil
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

// MARK: - Header View for Controls
private struct CompactEpisodeHeaderView: View {
    @ObservedObject var viewModel: ShowEpisodesViewModel
    @State private var showingFilters = false
    
    var body: some View {
        HStack {
            // Episode count and status
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.displayedEpisodes.count) episodes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !viewModel.searchText.isEmpty || viewModel.filterType != .all || viewModel.sortOrder != .newestFirst {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text("Filtered")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            Spacer()
            
            // Menu button
            Menu {
                Section("Search") {
                    Button(action: { showingFilters = true }) {
                        Label("Search & Filter", systemImage: "magnifyingglass")
                    }
                }
                
                Section("Quick Filters") {
                    ForEach(ShowEpisodesViewModel.EpisodeFilter.allCases) { filter in
                        Button(action: { viewModel.filterType = filter }) {
                            HStack {
                                Text(filter.rawValue)
                                if viewModel.filterType == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Section("Sort Order") {
                    ForEach(ShowEpisodesViewModel.EpisodeSortOrder.allCases) { sortOrder in
                        Button(action: { viewModel.sortOrder = sortOrder }) {
                            HStack {
                                Text(sortOrder.rawValue)
                                if viewModel.sortOrder == sortOrder {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button("Clear All Filters", role: .destructive) {
                        viewModel.searchText = ""
                        viewModel.filterType = .all
                        viewModel.sortOrder = .newestFirst
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingFilters) {
            EpisodeFilterSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Filter Sheet
private struct EpisodeFilterSheet: View {
    @ObservedObject var viewModel: ShowEpisodesViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Search Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search episodes...", text: $viewModel.searchText)
                        if !viewModel.searchText.isEmpty {
                            Button(action: { viewModel.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                // Filter Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filter")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("Filter", selection: $viewModel.filterType) {
                        ForEach(ShowEpisodesViewModel.EpisodeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Sort Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sort Order")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(ShowEpisodesViewModel.EpisodeSortOrder.allCases) { sortOrder in
                            Text(sortOrder.rawValue).tag(sortOrder)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Spacer()
                
                // Clear All Button
                Button("Clear All Filters") {
                    viewModel.searchText = ""
                    viewModel.filterType = .all
                    viewModel.sortOrder = .newestFirst
                }
                .foregroundColor(.red)
                .padding()
            }
            .padding()
            .navigationTitle("Search & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Reusable UI Components
private struct ErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
            Text(message).multilineTextAlignment(.center)
            Button("Retry", action: retryAction)
        }
        .padding()
    }
}

struct PaginatedEpisodeListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PaginatedEpisodeListView(podcast: .mock)
        }
    }
}

extension Podcast {
    static var mock: Podcast {
        Podcast(
            id: UUID(),
            title: "The Daily",
            author: "The New York Times",
            description: "This is what the news should sound like. The biggest stories of our time, told by the best journalists in the world. Hosted by Michael Barbaro and Sabrina Tavernise. Twenty minutes a day, five days a week, ready by 6 a.m.",
            feedURL: URL(string: "https://feeds.simplecast.com/54nAGcIl")!,
            artworkURL: URL(string: "https://source.unsplash.com/random/200x200?newspaper")
        )
    }
}

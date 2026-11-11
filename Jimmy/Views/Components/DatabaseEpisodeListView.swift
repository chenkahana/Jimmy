import SwiftUI
import Combine
import os

/// Database-backed episode list view that uses the same data source as LibraryView
/// This ensures consistent episode titles, played status, and other metadata
struct DatabaseEpisodeListView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DatabaseEpisodeListView")
    let podcastID: UUID
    let podcastTitle: String
    let podcastArtworkURL: URL?
    let filterOption: PodcastDetailViewModel.EpisodeFilter
    let sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    let onEpisodeTap: (EpisodeWithPlaybackState) -> Void
    
    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var episodePlaybackStates: [UUID: PlaybackState] = [:]
    
    private let episodeRepository = DIContainer.shared.episodeRepository
    private let progressCache = DIContainer.shared.progressCacheStore
    
    var body: some View {
        Group {
            if isLoading && episodes.isEmpty {
                loadingView
            } else if episodes.isEmpty && !isLoading {
                emptyView
            } else {
                episodesList
            }
        }
        .onAppear {
            loadEpisodes()
        }
        // Subscribe to real-time progress updates
        .onReceive(progressCache.$progressPercentageMap) { _ in
            // Trigger UI refresh when progress updates
            // SwiftUI will automatically re-render episode cards with new progress
        }
        // ⚠️ CRITICAL WARNING: DO NOT REMOVE THIS NOTIFICATION LISTENER
        // 
        // PURPOSE: Listens for episode status changes (played/unplayed) from EpisodeService
        // ESSENTIAL FOR: Real-time UI updates when user marks episodes as played in PodcastDetailView
        // 
        // FLOW: EpisodeService.updateEpisodeStatus() → posts .episodeStatusUpdated → this listener → updateEpisodeStatus()
        // 
        // WITHOUT THIS: Episode status changes won't appear in PodcastDetailView until app restart
        // 
        // FILTER: Only processes episodes belonging to this podcast (podcastID match)
        // SAFETY: Checks notification.object is Episode type before processing
        //
        // ⚠️ MODIFICATION WARNING: Changes here affect real-time episode status sync across views
        .onReceive(NotificationCenter.default.publisher(for: .episodeStatusUpdated)) { notification in
            if let updatedEpisode = notification.object as? Episode,
               updatedEpisode.podcastID == podcastID {
                logger.debug("DatabaseEpisodeListView: Received notification for episode \(updatedEpisode.title) with status: \(String(updatedEpisode.status.rawValue))")
                updateEpisodeStatus(updatedEpisode)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .episodeAddedToQueue)) { notification in
            // CRITICAL FIX: Refresh playback states when episode is added to queue
            if let episodeID = notification.object as? UUID {
                Task {
                    await loadPlaybackState(for: episodeID)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .episodeRemovedFromQueue)) { notification in
            // CRITICAL FIX: Refresh playback states when episode is removed from queue
            if let episodeID = notification.object as? UUID {
                Task {
                    await loadPlaybackState(for: episodeID)
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading episodes...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Episodes Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("This podcast may not have any episodes yet.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Button("Retry") {
                loadEpisodes()
            }
            .buttonStyle(.borderedProminent)
            .font(.caption)
        }
        .padding()
    }
    
    private var episodesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredAndSortedEpisodes, id: \.id) { episode in
                let episodeWithStatus = convertToEpisodeWithStatus(episode)
                
                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        let episodeWithState = EpisodeWithPlaybackState(
                            episode: episode,
                            playbackState: PlaybackState(
                                episodeID: episode.id,
                                position: episode.playbackPosition,
                                finished: episode.played || episode.status.contains(.played),
                                updatedAt: Date()
                            )
                        )
                        onEpisodeTap(episodeWithState)
                    },
                    onPlay: {
                        AudioPlayerService.shared.loadEpisode(episode, startPlaying: true)
                    },
                    onAddToQueue: {
                        Task {
                            await AppModel.current?.enqueue(episode.id)
                        }
                    },
                    onToggleFinished: {
                        Task {
                            await toggleEpisodePlayedStatus(episode)
                        }
                    }
                )
                .episodeContextMenu(
                    episode: episode,
                    onAddToQueue: {
                        Task {
                            await AppModel.current?.enqueue(episode.id)
                        }
                    },
                    onMarkAsPlayed: {
                        Task {
                            await toggleEpisodePlayedStatus(episode)
                        }
                    },
                    onPlayNext: {
                        Task {
                            await AppModel.current?.playNext(episode.id)
                        }
                    },
                    onShare: {
                        shareEpisode(episode)
                    }
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Data Processing
    
    private var filteredAndSortedEpisodes: [Episode] {
        var filtered = episodes
        
        // Apply filter
        switch filterOption {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { !$0.played && !$0.status.contains(.played) }
        case .played:
            filtered = filtered.filter { $0.played || $0.status.contains(.played) }
        case .downloaded:
            filtered = filtered.filter { $0.localFileURL != nil }
        }
        
        // Apply sort
        switch sortOrder {
        case .newestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) > ($1.publishedDate ?? Date.distantPast) }
        case .oldestFirst:
            filtered.sort { ($0.publishedDate ?? Date.distantPast) < ($1.publishedDate ?? Date.distantPast) }
        case .titleAZ:
            filtered.sort { $0.title < $1.title }
        case .titleZA:
            filtered.sort { $0.title > $1.title }
        }
        
        return filtered
    }
    
    private func convertToEpisodeWithStatus(_ episode: Episode) -> EpisodeWithStatus {
        let audioPlayer = AudioPlayerService.shared
        
        // Get real-time progress from cache first, then fallback to database/episode data
        let playProgress: Double
        let isQueued: Bool
        
       // print("🔍 DatabaseEpisodeListView: Processing episode '\(episode.title.prefix(30))' (ID: \(episode.id))")
       // print("🔍 DatabaseEpisodeListView: Episode duration: \(episode.duration ?? 0)s, playbackPosition: \(episode.playbackPosition)s")
        
        // Check if this is the currently playing episode
        if let currentEpisode = AudioPlayerService.shared.currentEpisode {
            if episode.id == currentEpisode.id {
                logger.debug("DatabaseEpisodeListView: This IS the currently playing episode")
            } else if episode.title == currentEpisode.title {
                logger.warning("DatabaseEpisodeListView: Same title as current episode but DIFFERENT ID")
                logger.debug("DatabaseEpisodeListView: Current episode ID: \(currentEpisode.id)")
                logger.debug("DatabaseEpisodeListView: This episode ID: \(episode.id)")
            }
        }
        
        // CRITICAL FIX: Update progress cache with episode duration FIRST
        if episode.duration != nil && episode.duration! > 0 {
            progressCache.updateProgressPercentage(for: episode.id, duration: episode.duration!)
           // print("🔍 DatabaseEpisodeListView: Updated cache with duration \(episode.duration!)s")
        }
        
        // CRITICAL FIX: Check if episode exists in cache (including 0% progress)
        // Don't use > 0 check because 0% is valid progress
        if progressCache.hasProgress(for: episode.id) {
            // Episode is in cache - use cached value (could be 0% or any value)
            playProgress = progressCache.getProgressPercentage(for: episode.id)
           // print("🔍 DatabaseEpisodeListView: Using cached progress: \(playProgress * 100)%")
            
            // CRITICAL FIX: Check queue status from AppModel directly for real-time updates
            isQueued = AppModel.current?.isQueued(episode.id) ?? false
           // print("🔍 DatabaseEpisodeListView: Queue status from AppModel: \(isQueued)")
        } else if let cachedState = episodePlaybackStates[episode.id] {
            // Priority 2: Database cached state
            playProgress = episode.duration != nil && episode.duration! > 0 
                ? cachedState.position / episode.duration! 
                : 0.0
            // CRITICAL FIX: Check queue status from AppModel directly for real-time updates
            isQueued = AppModel.current?.isQueued(episode.id) ?? false
           // print("🔍 DatabaseEpisodeListView: Using database cached state: \(playProgress * 100)%, queue: \(isQueued)")
        } else {
            // Priority 3: Fallback to episode's stored position
            playProgress = episode.duration != nil && episode.duration! > 0 
                ? episode.playbackPosition / episode.duration! 
                : 0.0
            // CRITICAL FIX: Check queue status from AppModel directly for real-time updates
            isQueued = AppModel.current?.isQueued(episode.id) ?? false
           // print("🔍 DatabaseEpisodeListView: Using fallback position: \(playProgress * 100)%, queue: \(isQueued)")
            
            // Load playback state asynchronously
            Task {
                await loadPlaybackState(for: episode.id)
            }
        }
        
        // Determine status using the derivation rules
        let isCurrentlyPlaying = audioPlayer.isPlaying && audioPlayer.currentEpisode?.id == episode.id
        
        let status = EpisodeWithStatus.deriveStatus(
            episode: episode,
            playProgress: playProgress,
            isQueued: isQueued,
            isCurrentlyPlaying: isCurrentlyPlaying
        )
        
       // print("🔍 DatabaseEpisodeListView: Final EpisodeWithStatus - playProgress: \(playProgress * 100)%, status: \(status)")
        
        return EpisodeWithStatus(
            episode: episode,
            podcastTitle: podcastTitle,
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcastArtworkURL
        )
    }
    
    // MARK: - Data Loading
    
    private func loadPlaybackState(for episodeID: UUID) async {
        do {
            if let playbackState = try await DIContainer.shared.playbackStateRepository.fetchPlaybackState(for: episodeID) {
                await MainActor.run {
                    episodePlaybackStates[episodeID] = playbackState
                }
            }
        } catch {
            logger.error("Failed to load playback state for episode \(episodeID): \(error)")
        }
    }
    
    private func loadEpisodes() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // First try to load from database (same as LibraryViewModel)
                let loadedEpisodes = try await episodeRepository.fetchAllEpisodes(for: podcastID, ignoreCache: false)
                
                if !loadedEpisodes.isEmpty {
                    // Found episodes in database
                    await MainActor.run {
                        // CRITICAL FIX: Preserve playback states from database
                        self.episodes = loadedEpisodes.map { episodeWithState in
                            var episode = episodeWithState.episode
                            // Update episode with current playback position from database
                            episode.playbackPosition = episodeWithState.playbackState.position
                            episode.played = episodeWithState.playbackState.finished
                            return episode
                        }
                        
                        // CRITICAL FIX: Also populate episodePlaybackStates cache
                        for episodeWithState in loadedEpisodes {
                            self.episodePlaybackStates[episodeWithState.episode.id] = episodeWithState.playbackState
                            if episodeWithState.playbackState.position > 0 {
                               // print("🔍 DatabaseEpisodeListView: Cached episode '\(episodeWithState.episode.title.prefix(20))' with position: \(episodeWithState.playbackState.position)s")
                            }
                        }
                        
                        self.isLoading = false
                       // print("🔍 DatabaseEpisodeListView: Loaded \(self.episodes.count) episodes with playback states")
                    }
                } else {
                    // No episodes in database, need to fetch from RSS feed
                    await fetchEpisodesFromNetwork()
                }
                
            } catch {
                // Database error, try fetching from network as fallback
                await fetchEpisodesFromNetwork()
            }
        }
    }
    
    /// Fetch episodes from RSS feed when not available in database
    private func fetchEpisodesFromNetwork() async {
        do {
            // Get the podcast to access its feed URL
            let podcasts = try await DIContainer.shared.subscriptionRepository.fetchSubscriptions(ignoreCache: false)
            guard let podcast = podcasts.first(where: { $0.id == podcastID }) else {
                await MainActor.run {
                    self.errorMessage = "Podcast not found"
                    self.isLoading = false
                }
                return
            }
            
            // Use the same streaming service as LibraryViewModel
            let streamingService = SimpleStreamingEpisodeService.shared
            var fetchedEpisodes: [Episode] = []
            
            // Stream episodes from RSS feed
            for try await episode in streamingService.streamEpisodes(from: podcast.feedURL, podcastID: podcastID) {
                fetchedEpisodes.append(episode)
                
                // Update UI with episodes as they arrive (like LibraryViewModel)
                await MainActor.run {
                    self.episodes = fetchedEpisodes
                }
                
                // Limit to prevent memory issues
                if fetchedEpisodes.count >= 100 {
                    break
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func updateEpisodeStatus(_ updatedEpisode: Episode) {
        // First try to find by ID
        if let index = episodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
            episodes[index] = updatedEpisode
            logger.debug("DatabaseEpisodeListView: Updated episode \(updatedEpisode.title) by ID match with status: \(String(updatedEpisode.status.rawValue))")
        } else {
            // If not found by ID, try to find by title and podcast (same logic as LibraryViewModel)
            if let index = episodes.firstIndex(where: { 
                $0.title == updatedEpisode.title && $0.podcastID == updatedEpisode.podcastID 
            }) {
                episodes[index] = updatedEpisode
                logger.debug("DatabaseEpisodeListView: Updated episode \(updatedEpisode.title) by title match with status: \(String(updatedEpisode.status.rawValue))")
            } else {
                logger.warning("DatabaseEpisodeListView: Episode \(updatedEpisode.title) not found in local episodes (total: \(episodes.count))")
            }
        }
        
        // CRITICAL FIX: Also update LibraryViewModel's cache to prevent duplicates
        // WorldClass engine handles all episode updates automatically
    }
    
    private func toggleEpisodePlayedStatus(_ episode: Episode) async {
        logger.debug("DatabaseEpisodeListView: toggleEpisodePlayedStatus called for \(episode.title) (ID: \(episode.id))")
        
        // CRITICAL FIX: Don't use getEpisodeWithStatus as it can return corrupted data
        // Instead, work with the original episode and only check its current status
        let isCurrentlyPlayed = episode.status.contains(.played)
        
       // print("🔍 DatabaseEpisodeListView: Current played status: \(isCurrentlyPlayed), Episode status: \(episode.status)")
        
        if isCurrentlyPlayed {
            // Remove played status - preserve all episode data
            var newStatus = episode.status
            newStatus.remove(.played)
            EpisodeService.shared.updateEpisodeStatus(episode, status: newStatus)
            logger.debug("DatabaseEpisodeListView: Removing played status from \(episode.title)")
        } else {
            // Mark as played - preserve all episode data
            EpisodeService.shared.setEpisodePlayed(episode)
            logger.debug("DatabaseEpisodeListView: Setting \(episode.title) as played")
        }
        
        // IMMEDIATE UI UPDATE: Update local state immediately for responsiveness
        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            var updatedEpisode = episode
            if isCurrentlyPlayed {
                updatedEpisode.status.remove(.played)
                updatedEpisode.played = false  // Sync legacy field
            } else {
                updatedEpisode.status.insert(.played)
                updatedEpisode.played = true   // Sync legacy field
            }
            episodes[index] = updatedEpisode
            let dbEpStatusStr = String(updatedEpisode.status.rawValue)
            logger.debug("DatabaseEpisodeListView: Updated local episode \(updatedEpisode.title) with status: \(dbEpStatusStr), played: \(updatedEpisode.played)")
        }
    }
    
    private func shareEpisode(_ episode: Episode) {
        // Share functionality will be handled by the context menu modifier
    }
} 
import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CryptoKit
import GRDB
import os

class AudioPlayerService: NSObject, ObservableObject {
    static let shared = AudioPlayerService()
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AudioPlayerService")
    
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentEpisode: Episode?
    @Published var playbackPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var currentAudioRoute: AudioRouteType = .speaker
    
    // Throttled publisher for playback progress
    let playbackProgressPublisher = PassthroughSubject<Double, Never>()
    
    // Enhanced publisher that includes episode ID for progress tracking
    let episodeProgressPublisher = PassthroughSubject<(UUID, Double), Never>()
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    private let podcastRepository: PodcastRepositoryProtocol
    private var currentPodcast: Podcast?
    
    // Progress saving properties
    private var lastSaveTime: Date = Date()
    private let saveInterval: TimeInterval = 3.0 // Save progress every 3 seconds to reduce DB load
    
    // REMOVED: AVPlayerItem caching causes crashes when reused across AVPlayer instances
    // Each AVPlayer needs its own AVPlayerItem - no sharing allowed
    private let playerQueue = DispatchQueue(label: "audioPlayer", qos: .userInitiated)
    
    private init(
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository,
        podcastRepository: PodcastRepositoryProtocol = DIContainer.shared.podcastRepository
    ) {
        self.playbackStateRepository = playbackStateRepository
        self.podcastRepository = podcastRepository
        super.init()
        
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotificationObservers()
        setupProgressPublisher()
        setupAudioRouteMonitoring()
        
        // Wait for database to be ready before restoring episode
        Task {
            await DatabaseManager.shared.waitForReady()
            await restoreLastPlayingEpisode()
        }
    }
    
    deinit {
        // CRITICAL: Safe cleanup to prevent crashes
        cleanupAudioPlayer()
        NotificationCenter.default.removeObserver(self)
        cancellables.forEach { $0.cancel() }
    }
    
    /// Safely cleanup audio player and time observer to prevent crashes
    private func cleanupAudioPlayer() {
        // CRITICAL: Always clean up time observer before releasing player
        if let observer = timeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Clean up player
        if let currentPlayer = player {
            currentPlayer.pause()
        }
        
        player = nil
    }
    
    private func setupProgressPublisher() {
        $playbackPosition
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] position in
                guard let self = self else { return }
                
                // Send legacy progress update
                self.playbackProgressPublisher.send(position)
                
                // Send enhanced progress update with episode ID
                if let currentEpisode = self.currentEpisode {
                    self.episodeProgressPublisher.send((currentEpisode.id, position))
                }
            }
            .store(in: &cancellables)
    }
    
    func loadEpisode(_ episode: Episode, startPlaying: Bool = false, isRestoration: Bool = false) {
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            self.currentEpisode = episode
            self.isLoading = true
            
            // Save the current episode ID for restoration after app restart
            // Always save, even during restoration, to ensure it's current
            UserDefaults.standard.set(episode.id.uuidString, forKey: "lastPlayingEpisodeID")
            Self.logger.debug("Saved episode ID to UserDefaults: \(episode.id.uuidString)")
        }
        
        // Update episode status and queue position if not restoring
        if !isRestoration {
            Task.detached(priority: .utility) {
                EpisodeService.shared.setEpisodePlaying(episode)

                // "Play Now": the episode always ends up at position 1, whether it was already
                // queued (moved) or not (inserted) — `AppModel.enqueue` handles both.
                if startPlaying {
                    Self.logger.debug("Implementing Play Now: ensuring episode is at queue position 1")
                    await AppModel.current?.enqueue(episode.id, at: 1)
                }
            }
        }
        
        Task {
            // CRITICAL FIX: Load podcast information FIRST before trying to save episode
            // This ensures currentPodcast is available when we need to determine podcastID
            if let podcastID = episode.podcastID {
                self.currentPodcast = try? await podcastRepository.fetchPodcast(id: podcastID, ignoreCache: false)
                let podcastTitle = self.currentPodcast?.title ?? "Unknown"
                Self.logger.debug("Loaded podcast: \(podcastTitle)")
            } else {
                Self.logger.warning("Episode has no podcastID - will try to infer from context")
            }
            
            // CRITICAL FIX: Ensure episode is saved to database for future restoration
            // This is necessary because episodes might be played without being fetched from RSS
            do {
                // Check if episode exists in database
                let existingEpisode = try await DIContainer.shared.episodeRepository.fetchEpisode(by: episode.id)
                if existingEpisode == nil {
                    // Episode doesn't exist in database, save it
                    Self.logger.debug("Episode not in database, saving for future restoration: \(episode.title)")
                    
                    // CRITICAL FIX: Ensure episode has a valid podcastID before saving
                    var episodeToSave = episode
                    if episodeToSave.podcastID == nil {
                        // Try to determine podcast ID from current podcast
                        if let currentPodcastID = self.currentPodcast?.id {
                            episodeToSave.podcastID = currentPodcastID
                            Self.logger.debug("Set episode podcastID to current podcast: \(currentPodcastID)")
                        } else {
                            // FALLBACK 1: Try to find podcast by episode metadata
                            Self.logger.debug("Attempting to find podcast by episode metadata")
                            if let foundPodcastID = try? await self.findPodcastIDForEpisode(episode) {
                                episodeToSave.podcastID = foundPodcastID
                                Self.logger.debug("Found podcast ID via episode search: \(foundPodcastID)")
                                // Also set currentPodcast for future episodes
                                if let foundPodcast = try? await self.podcastRepository.fetchPodcast(id: foundPodcastID, ignoreCache: false) {
                                    self.currentPodcast = foundPodcast
                                    Self.logger.debug("Set current podcast: \(foundPodcast.title)")
                                }
                            } else if let audioURL = episode.audioURL, let audioHost = audioURL.host {
                                // FALLBACK 2: Create deterministic podcast ID from audio URL domain
                                // This implements your brilliant "use feed URL as ID" concept
                                Self.logger.debug("Creating deterministic podcast ID from audio domain: \(audioHost)")
                                guard let syntheticFeedURL = URL(string: "https://\(audioHost)/feed") else {
                                    Self.logger.error("Failed to create synthetic feed URL for host: \(audioHost)")
                                    return
                                }
                                let deterministicID = self.deterministicUUID(from: syntheticFeedURL)
                                episodeToSave.podcastID = deterministicID
                                Self.logger.debug("Generated deterministic podcast ID: \(deterministicID)")
                                Self.logger.debug("This ensures episodes from the same domain get the same podcast ID")
                            } else {
                                Self.logger.warning("Cannot save episode without valid podcastID")
                                Self.logger.warning("Episode will not be restorable until played from a known podcast")
                                let curPodcastTitle = self.currentPodcast?.title ?? "None"
                                Self.logger.debug("Current podcast: \(curPodcastTitle)")
                                Self.logger.debug("Episode details: \(episode.title)")
                                let audioURLStr = episode.audioURL?.absoluteString ?? "None"
                                Self.logger.debug("Audio URL: \(audioURLStr)")
                                return // Don't save episodes without valid podcast IDs
                            }
                        }
                    }
                    
                    // Create EpisodeWithPlaybackState for saving
                    let playbackState = PlaybackState(episodeID: episode.id, position: 0, finished: false)
                    let episodeWithState = EpisodeWithPlaybackState(episode: episodeToSave, playbackState: playbackState)
                    
                    guard let podcastID = episodeToSave.podcastID else {
                        Self.logger.warning("Cannot save episode: missing podcastID")
                        return
                    }
                    try await DIContainer.shared.episodeRepository.saveEpisodes([episodeWithState], for: podcastID)
                    Self.logger.info("Episode saved to database for future restoration with podcastID: \(podcastID)")
                } else {
                    let existingPodcastIDStr = existingEpisode?.episode.podcastID?.uuidString ?? "None"
                    Self.logger.debug("Episode already exists in database with podcastID: \(existingPodcastIDStr)")
                }
            } catch {
                Self.logger.error("Failed to save episode to database: \(error)")
            }
            
            let state = try? await playbackStateRepository.fetchPlaybackState(for: episode.id)
            let startTime = state?.position ?? 0
            

            
            // Check for local downloaded file first, then fall back to remote URL
            guard let url = DownloadManager.shared.effectiveURL(for: episode) else {
                await MainActor.run {
                    self.isLoading = false
                }
                return
            }
            
            // CRITICAL: Clean up existing player and time observer before creating new one
            await MainActor.run {
                self.cleanupAudioPlayer()
            }
            
            // CRITICAL: Always create a new AVPlayerItem - never reuse
            // Reusing AVPlayerItems across AVPlayer instances causes crashes
            let playerItem = AVPlayerItem(url: url)
            
            await MainActor.run {
                self.player = AVPlayer(playerItem: playerItem)
                self.player?.rate = self.playbackSpeed
                self.isLoading = false
                

                
                // Wait for the player item to be ready before seeking
                if startTime > 0 {
                    // Use KVO to wait for the player item to be ready
                    self.seekWhenReady(to: startTime, playerItem: playerItem)
                } else {
                    self.duration = playerItem.asset.duration.seconds
                    self.playbackPosition = 0
                }
                
                if startPlaying {
                    self.play()
                } else {
                    // Explicitly ensure the player is paused during restoration
                    self.player?.pause()
                    self.isPlaying = false
                }
                
                self.addPeriodicTimeObserver()
                self.updateNowPlayingInfo()
            }
        }
    }
    
    private func seekWhenReady(to time: TimeInterval, playerItem: AVPlayerItem) {
        // Check if the player item is ready
        if playerItem.status == .readyToPlay {
            self.duration = playerItem.asset.duration.seconds
            self.seek(to: time)
        } else {
            // Wait for the player item to be ready
            let observer = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                if item.status == .readyToPlay {
                    DispatchQueue.main.async {
                        self?.duration = item.asset.duration.seconds
                        self?.seek(to: time)
                    }
                }
            }
            
            // Store the observer to clean it up later
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                observer.invalidate()
            }
        }
    }
    
    func play() {
        guard let player = player else { return }
        
        // CRITICAL: Apply the correct playback speed when starting playback
        player.rate = playbackSpeed
        player.play()
        
        // CRITICAL: Ensure UI updates happen on main thread
        Task { @MainActor in
            self.isPlaying = true
        }

        // Start listening stats tracking
        ListeningStatsService.shared.startTracking(podcastID: currentEpisode?.podcastID?.uuidString)

        if let episode = currentEpisode {
            Log.playback.info("Episode play: \(episode.id.uuidString, privacy: .public) podcast=\(episode.podcastID?.uuidString ?? "unknown", privacy: .public)")
        }
        
        updateNowPlayingInfo()
        Task { @MainActor in await SharedDataStore.shared.updateWidgetData() }
    }

    func pause() {
        guard let player = player else { return }

        player.pause()

        // Stop listening stats tracking
        ListeningStatsService.shared.stopTracking()

        // CRITICAL: Ensure UI updates happen on main thread
        Task { @MainActor in
            self.isPlaying = false
        }

        if let episode = currentEpisode {
            Log.playback.info("Episode pause: \(episode.id.uuidString, privacy: .public) position=\(self.playbackPosition)")
        }
        
        // Save state in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.savePlaybackState()
        }
        
        updateNowPlayingInfo()
        Task { @MainActor in await SharedDataStore.shared.updateWidgetData() }
    }

    func stop() {
        // Clear playing status from current episode in background
        if let episode = currentEpisode {
            Task.detached(priority: .utility) {
                EpisodeService.shared.clearEpisodePlaying(episode)
            }
        }
        
        // Save state in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.savePlaybackState()
        }
        
        // CRITICAL: Use safe cleanup method
        cleanupAudioPlayer()
        
        // CRITICAL: Ensure main thread updates for @Published properties
        Task { @MainActor in
            self.currentEpisode = nil
            self.currentPodcast = nil
            self.isPlaying = false
            self.playbackPosition = 0
            self.duration = 0
            
            // DON'T clear the saved episode ID here - let it persist for restoration
            // Only clear it when user explicitly stops or finishes an episode
            // UserDefaults.standard.removeObject(forKey: "lastPlayingEpisodeID")
            Self.logger.debug("Stopped playback but preserved episode ID for restoration")
        }
        
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        let previousPosition = playbackPosition
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 1))
        playbackPosition = time
        
        if let episode = currentEpisode, abs(time - previousPosition) > 1.0 {
            Log.playback.info("Episode seek: \(episode.id.uuidString, privacy: .public) from=\(previousPosition) to=\(time)")
        }
        
        // Save playback state in background
        Task.detached(priority: .utility) { [weak self] in
            await self?.savePlaybackState()
        }
        
        updateNowPlayingInfo()
    }

    private func addPeriodicTimeObserver() {
        // CRITICAL: Ensure we're on main thread and properly clean up existing observer
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.addPeriodicTimeObserver()
            }
            return
        }
        
        // Remove existing observer from the SAME player instance to prevent crashes
        if let observer = timeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // CRITICAL: Use weak self and ensure main thread updates
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // CRITICAL: Ensure we're updating @Published on main thread
            Task { @MainActor in
                self.playbackPosition = time.seconds
                
                // Check if episode should be marked as played (>95% complete)
                if let episode = self.currentEpisode, self.duration > 0 {
                    let progress = self.playbackPosition / self.duration
                    if progress > 0.95 && !episode.status.contains(.played) {
                        // Do this in background to avoid blocking UI
                        Task.detached(priority: .utility) {
                            EpisodeService.shared.setEpisodePlayed(episode)
                        }
                    }
                }
                
                // Periodically save state in background
                if Date().timeIntervalSince(self.lastSaveTime) > self.saveInterval {
                    Task.detached(priority: .utility) { [weak self] in
                        await self?.savePlaybackState()
                    }
                    self.lastSaveTime = Date() // Update immediately to prevent duplicate saves
                }
            }
        }
    }

    private func savePlaybackState() async {
        guard let episode = currentEpisode else { 
            Self.logger.warning("No current episode to save state for")
            return 
        }
        
        let state = PlaybackState(episodeID: episode.id, position: playbackPosition, finished: false)
        let positionStr = String(format: "%.1f", state.position)
        Self.logger.debug("Attempting to save progress: \(positionStr)s for episode: \(episode.title)")
        
        do {
            try await playbackStateRepository.savePlaybackState(state)
            lastSaveTime = Date()
            Self.logger.debug("Successfully saved playback state")
        } catch {
            Self.logger.error("Failed to save playback state: \(error)")
        }
    }
    
    private func restoreLastPlayingEpisode() async {
        // CRITICAL FIX: Only restore if user has enabled auto-restore setting
        let autoRestore = UserDefaults.standard.bool(forKey: "autoRestoreLastEpisode")
        if !autoRestore {
            Self.logger.debug("Auto-restore disabled by user - skipping episode restoration")
            return
        }
        
        Self.logger.info("Starting episode restoration process")
        
        do {
            // First try UserDefaults for the last playing episode (most recent approach)
            if let episodeIDString = UserDefaults.standard.string(forKey: "lastPlayingEpisodeID") {
                Self.logger.debug("Found saved episode ID: \(episodeIDString)")
                
                if let episodeID = UUID(uuidString: episodeIDString) {
                    Self.logger.debug("Attempting to fetch episode from database")
                    
                    // Try to fetch episode from database
                    if let episodeWithState = try await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) {
                        Self.logger.info("Successfully fetched episode: \(episodeWithState.episode.title)")
                        Self.logger.debug("Episode playback position: \(episodeWithState.playbackState.position)s")
                        
                        await MainActor.run {
                            Task {
                                Self.logger.info("Loading restored episode: \(episodeWithState.episode.title)")
                                await self.loadEpisode(episodeWithState.episode, startPlaying: false, isRestoration: true)
                                
                                // CRITICAL FIX: Ensure restored episode is at queue position 1
                                // The currently playing episode should always be at position 1
                                Self.logger.debug("Ensuring restored episode is at queue position 1")
                                await AppModel.current?.enqueue(episodeWithState.episode.id, at: 1)
                                
                                // CRITICAL FIX: Manually seek to the saved position after loadEpisode completes
                                // We need to do this because loadEpisode might not get the correct playback state
                                let savedPosition = episodeWithState.playbackState.position
                                if savedPosition > 0 {
                                    Self.logger.debug("Manually seeking to saved position: \(savedPosition)s")
                                    // Wait a bit for the player to be ready, then seek
                                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                                    self.seek(to: savedPosition)
                                    Self.logger.info("Restored playback position: \(savedPosition)s")
                                } else {
                                    Self.logger.debug("No seek needed - episode starts from beginning")
                                }
                                
                                Self.logger.info("Episode restoration complete")
                            }
                        }
                        return
                    } else {
                        Self.logger.warning("Episode not found in database, checking if playback state exists")
                        
                        // FALLBACK: Episode missing from episodes table but playback state might exist
                        // This can happen if episode was played before our persistence fix
                        if let playbackState = try await playbackStateRepository.fetchPlaybackState(for: episodeID) {
                            Self.logger.debug("Found orphaned playback state with position: \(playbackState.position)s")
                            Self.logger.warning("Episode data missing - cannot restore without episode details")
                            Self.logger.debug("Suggestion: Play the episode again to save it to database for future restoration")
                            
                            // Clean up orphaned playback state
                            Self.logger.debug("Cleaning up orphaned playback state")
                            try? await cleanupOrphanedPlaybackState(episodeID: episodeID)
                            
                            // Clear the saved episode ID since we can't restore it
                            await MainActor.run {
                                UserDefaults.standard.removeObject(forKey: "lastPlayingEpisodeID")
                                Self.logger.debug("Cleared invalid episode ID from UserDefaults")
                            }
                        } else {
                            Self.logger.warning("No playback state found either")
                            
                            // DEBUG: Let's see what's actually in the database for this episode
                            await self.debugEpisodeInDatabase(episodeID: episodeID)
                        }
                    }
                } else {
                    Self.logger.error("Invalid episode ID format")
                }
            } else {
                Self.logger.debug("No saved episode ID found in UserDefaults")
            }
            
            // Fallback: Get the next episode in queue (position 1)
            Self.logger.debug("Trying fallback: fetching next queued episode")
            if let nextEpisodeID = await AppModel.current?.queue.first?.id,
               let nextEpisode = try await DIContainer.shared.episodeRepository.fetchEpisode(by: nextEpisodeID) {
                Self.logger.debug("Found queued episode: \(nextEpisode.episode.title) at \(nextEpisode.playbackState.position)s")

                await MainActor.run {
                    Task {
                        await self.loadEpisode(nextEpisode.episode, startPlaying: false, isRestoration: true)

                        if nextEpisode.playbackState.position > 0 {
                            Self.logger.debug("Seeking to queued episode position: \(nextEpisode.playbackState.position)s")
                            self.seek(to: nextEpisode.playbackState.position)
                        }
                    }
                }
            } else {
                Self.logger.debug("No queued episodes found")
                Self.logger.debug("To restore episodes: play an episode and it will be available after restart")
            }
        } catch {
            Self.logger.error("Failed to restore episode: \(error)")
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = currentPodcast?.title ?? "Podcast"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = currentPodcast?.title
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 1.0
        
        // Load and set artwork for dynamic island and lock screen
        loadArtworkForNowPlaying(episode: episode) { artwork in
            if let artwork = artwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func loadArtworkForNowPlaying(episode: Episode, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        // Try episode artwork first, then fall back to podcast artwork
        let artworkURL = episode.artworkURL ?? currentPodcast?.artworkURL
        
        guard let url = artworkURL else {
            completion(nil)
            return
        }
        
        // Load artwork asynchronously with shorter timeout to reduce errors
        Task {
            do {
                let request = URLRequest(url: url, timeoutInterval: 5.0)
                let (data, _) = try await URLSession.shared.data(for: request)
                
                guard let image = UIImage(data: data) else {
                    await MainActor.run { completion(nil) }
                    return
                }
                
                // Create artwork with proper size handling
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                    return image
                }
                
                await MainActor.run {
                    completion(artwork)
                }
            } catch {
                // Silently fail artwork loading to reduce console noise
                await MainActor.run {
                    completion(nil)
                }
            }
        }
    }
    
    @objc private func handleEpisodeDidEnd(_ notification: Notification) {
        guard let episode = currentEpisode else { return }
        
        Log.playback.info("Episode complete: \(episode.id.uuidString, privacy: .public) podcast=\(episode.podcastID?.uuidString ?? "unknown", privacy: .public) duration=\(self.duration)")
        
        // Mark episode as finished
        let state = PlaybackState(episodeID: episode.id, position: 0, finished: true)
        Task {
            try? await playbackStateRepository.savePlaybackState(state)
            
            // Mark episode as played
            EpisodeService.shared.setEpisodePlayed(episode)
            
            // Clear the saved episode ID since this episode is now finished
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "lastPlayingEpisodeID")
                Self.logger.debug("Episode finished, cleared saved episode ID")
            }
        }
        
        // Auto-advance to next episode with slight delay to prevent race conditions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.playNext()
        }
    }
    
    /// Debug method to see what's actually in the database for an episode
    private func debugEpisodeInDatabase(episodeID: UUID) async {
        do {
            try await DatabaseManager.shared.readAsync { db in
                // Check if episode exists in episodes table
                let episodeRows = try Row.fetchAll(db, sql: "SELECT id, podcastID, title FROM episodes WHERE id = ?", arguments: [episodeID.uuidString])
                if let episodeRow = episodeRows.first {
                    let podcastID = episodeRow["podcastID"] as? String ?? "nil"
                    let title = episodeRow["title"] as? String ?? "Unknown"
                    Self.logger.debug("DEBUG: Episode found in database")
                    Self.logger.debug("Episode ID: \(episodeID)")
                    Self.logger.debug("Episode Title: \(title)")
                    Self.logger.debug("Episode PodcastID: \(podcastID)")
                    
                    // Check if the podcast exists
                    let podcastRows = try Row.fetchAll(db, sql: "SELECT id, title FROM podcasts WHERE id = ?", arguments: [podcastID])
                    if let podcastRow = podcastRows.first {
                        let podcastTitle = podcastRow["title"] as? String ?? "Unknown"
                        Self.logger.debug("Podcast exists: \(podcastTitle)")
                    } else {
                        Self.logger.warning("Podcast with ID \(podcastID) does not exist")
                        Self.logger.warning("Episode references non-existent podcast")
                    }
                } else {
                    Self.logger.debug("Episode not found in episodes table")
                }
                
                // Check playback_state table
                let playbackRows = try Row.fetchAll(db, sql: "SELECT * FROM playback_state WHERE episodeID = ?", arguments: [episodeID.uuidString])
                if let playbackRow = playbackRows.first {
                    let position = playbackRow["position"] as? Double ?? 0
                    let finished = playbackRow["finished"] as? Bool ?? false
                    Self.logger.debug("Playback state found: position=\(position), finished=\(finished)")
                } else {
                    Self.logger.debug("No playback state found")
                }
            }
        } catch {
            Self.logger.error("Debug error: \(error)")
        }
    }
    
    /// Clean up orphaned playback states that don't have corresponding episodes
    private func cleanupOrphanedPlaybackState(episodeID: UUID) async throws {
        // Remove the orphaned playback state from database
        try await DatabaseManager.shared.writeAsync { db in
            try db.execute(sql: "DELETE FROM playback_state WHERE episodeID = ?", arguments: [episodeID.uuidString])
        }
        Self.logger.info("Removed orphaned playback state for episode: \(episodeID)")
    }
    
    /// Try to find the podcast ID for an episode by searching existing podcasts
    private func findPodcastIDForEpisode(_ episode: Episode) async throws -> UUID? {
        // Get all podcasts and try to find a match
        let podcasts = try await podcastRepository.fetchPodcasts(ignoreCache: false)
        
        // If episode has audio URL, try to match by domain
        if let audioURL = episode.audioURL {
            let audioHost = audioURL.host?.lowercased()
            
            // First try exact domain matching with existing podcasts
            for podcast in podcasts {
                let feedHost = podcast.feedURL.host?.lowercased()
                if let audioHost = audioHost, let feedHost = feedHost, audioHost == feedHost {
                    Self.logger.debug("Matched episode to podcast by domain: \(podcast.title)")
                    return podcast.id
                }
            }
            
            // If no exact match found, check if any podcast should have a deterministic ID based on this domain
            for podcast in podcasts {
                let expectedID = deterministicUUID(from: podcast.feedURL)
                if expectedID == podcast.id {
                    // This podcast is already using deterministic IDs, check if domains match
                    let feedHost = podcast.feedURL.host?.lowercased()
                    if let audioHost = audioHost, let feedHost = feedHost, audioHost == feedHost {
                        Self.logger.debug("Matched episode to deterministic podcast by domain: \(podcast.title)")
                        return podcast.id
                    }
                }
            }
        }
        
        // Fallback: Try to match by episode title similarity (for shows with consistent naming)
        // This is a simple heuristic - in practice you might want more sophisticated matching
        for podcast in podcasts {
            if episode.title.lowercased().contains(podcast.title.lowercased().prefix(10)) {
                Self.logger.debug("Matched episode to podcast by title similarity: \(podcast.title)")
                return podcast.id
            }
        }
        
        return nil
    }
    
    /// Create a deterministic UUID from a feed URL
    /// This ensures the same feed URL always generates the same UUID, solving the podcast ID problem
    private func deterministicUUID(from feedURL: URL) -> UUID {
        let feedString = feedURL.absoluteString.lowercased() // Normalize case
        let data = feedString.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        
        // Convert first 16 bytes of hash to UUID
        let hashData = Data(hash)
        let uuidBytes = Array(hashData.prefix(16))
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        
        return uuid
    }

    
    // Keep other setup methods like setupAudioSession, setupRemoteTransportControls, etc.
    // ...
    
    private func setupAudioSession() {
        let success = CrashPreventionManager.shared.safeConfigureAudioSession(category: .playback)
        if !success { Self.logger.warning("Failed to configure audio session") }
    }
    

    

    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Enable commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardSeconds)]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            self?.seekForward()
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardSeconds)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            self?.seekBackward()
            return .success
        }
        
        // Handle seek command from control center/lock screen
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let seekEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: seekEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func setupNotificationObservers() {
        // Handle audio session interruptions (calls, alarms, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Handle audio route changes (headphones plugged/unplugged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        // Handle app going to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // Handle app becoming active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        // Handle app termination to save any pending data
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Handle episode completion for auto-advance
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEpisodeDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio session interrupted (call, alarm, etc.)
            if isPlaying {
                pause()
            }
        case .ended:
            // Interruption ended, can resume if was playing
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && currentEpisode != nil {
                    play()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged, pause playback
            if isPlaying {
                pause()
            }
        default:
            break
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Save current playback position before going to background
        if currentEpisode != nil {
            Task.detached(priority: .utility) { [weak self] in
                await self?.savePlaybackState()
            }
        }
        
        // Only keep audio session active if we're actually playing
        if isPlaying {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Self.logger.warning("Failed to keep audio session active in background: \(error)")
            }
        }
    }
    
    @objc private func appDidBecomeActive() {
        // Only reactivate audio session if we have a current episode and are playing
        if isPlaying && currentEpisode != nil {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                Self.logger.warning("Failed to reactivate audio session: \(error)")
            }
        }
        
        // Update UI with current playback state
        updateNowPlayingInfo()
    }
    
    @objc private func appWillTerminate() {
        // Save current playback position and episode ID before app terminates
        if currentEpisode != nil {
            // Use a synchronous approach for app termination to ensure data is saved
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached(priority: .utility) { [weak self] in
                await self?.savePlaybackState()
                semaphore.signal()
            }
            // Wait briefly for save to complete, but don't block termination indefinitely
            _ = semaphore.wait(timeout: .now() + 1.0)
        }
        
        // CRITICAL: Stop audio playback and deactivate audio session on app termination
        // This prevents audio from continuing to play after the app is closed
        if isPlaying {
            player?.pause()
            isPlaying = false
            
            // Deactivate audio session to completely stop background audio
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                Self.logger.warning("Failed to deactivate audio session on termination: \(error)")
            }
            
            // Clear now playing info from control center
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    

    
    // REMOVED: AVPlayerItem caching methods - they cause crashes when reused
    // Each episode load creates a fresh AVPlayerItem to avoid sharing conflicts
    
    func seek(by seconds: Double) {
        guard let player = player else { return }
        let currentTime = player.currentTime()
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1))
        let clampedTime = CMTimeClampToRange(newTime, range: CMTimeRange(start: .zero, duration: player.currentItem?.duration ?? .zero))
        
        player.seek(to: clampedTime) { [weak self] _ in
            Task { @MainActor in
                self?.playbackPosition = clampedTime.seconds
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    /// Current player volume (0.0 to 1.0)
    var volume: Float {
        player?.volume ?? 1.0
    }

    /// Set player volume (used by SleepTimerService for fade-out)
    func setVolume(_ value: Float) {
        player?.volume = max(0, min(1, value))
    }

    /// Configurable skip durations (defaults to 15s, updated from Settings)
    private var skipForwardSeconds: Double = {
        let val = UserDefaults.standard.double(forKey: "skipForwardDuration")
        return val > 0 ? val : 15.0
    }()
    private var skipBackwardSeconds: Double = {
        let val = UserDefaults.standard.double(forKey: "skipBackwardDuration")
        return val > 0 ? val : 15.0
    }()

    func seekForward() {
        seek(by: skipForwardSeconds)
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    func seekBackward() {
        seek(by: -skipBackwardSeconds)
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    /// Update skip durations from settings and refresh lock screen intervals
    func updateSkipDurations(forward: Double, backward: Double) {
        skipForwardSeconds = forward
        skipBackwardSeconds = backward
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forward)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backward)]
    }
    

    
    func playNext() {
        Task { @MainActor in
            guard let nextEpisodeID = AppModel.current?.queue.first?.id,
                  let nextEpisode = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: nextEpisodeID) else {
                Self.logger.info("No episodes in queue to play next")
                self.pause()
                return
            }

            // Remove it from the queue and play it
            await AppModel.current?.dequeue(nextEpisodeID)
            await self.loadEpisode(nextEpisode.episode, startPlaying: true, isRestoration: false)
        }
    }
    
    private func setupAudioRouteMonitoring() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateCurrentAudioRoute()
                }
            }
            .store(in: &cancellables)
        
        // Initial route detection
        Task { @MainActor in
            updateCurrentAudioRoute()
        }
    }
    
    private func updateCurrentAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else {
            currentAudioRoute = .speaker
            return
        }
        
        switch output.portType {
        case .builtInSpeaker:
            currentAudioRoute = .speaker
        case .headphones:
            currentAudioRoute = .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            if output.portName.lowercased().contains("airpods") {
                currentAudioRoute = .airpods
            } else {
                currentAudioRoute = .bluetooth
            }
        case .airPlay:
            currentAudioRoute = .airplay
        case .carAudio:
            currentAudioRoute = .carplay
        default:
            currentAudioRoute = .speaker
        }
    }

    func updatePlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        UserDefaults.standard.set(speed, forKey: "playbackSpeed")
        applyPlaybackSpeed()
    }

    private func applyPlaybackSpeed() {
        guard let player = player else { return }
        
        // CRITICAL FIX: Only apply speed if currently playing
        // For paused/stopped players, the speed will be applied when play() is called
        if isPlaying {
            player.rate = playbackSpeed
        }
        // Note: loadEpisode() sets player.rate directly, so restoration works fine
    }
    
    /// Clear any corrupted restoration state
    /// Call this if episodes fail to restore properly
    func clearRestorationState() {
        Task { @MainActor in
            UserDefaults.standard.removeObject(forKey: "lastPlayingEpisodeID")
            Self.logger.debug("Cleared restoration state")
        }
    }
}

// MARK: - Supporting Types

enum AudioRouteType: CaseIterable {
    case speaker
    case headphones
    case airpods
    case bluetooth
    case airplay
    case carplay
    
    var iconName: String {
        switch self {
        case .speaker:
            return "speaker.wave.3"
        case .headphones:
            return "headphones"
        case .airpods:
            return "airpodspro"
        case .bluetooth:
            return "hifispeaker.fill"
        case .airplay:
            return "airplayaudio"
        case .carplay:
            return "car.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .speaker:
            return "iPhone Speaker"
        case .headphones:
            return "Headphones"
        case .airpods:
            return "AirPods"
        case .bluetooth:
            return "Bluetooth Device"
        case .airplay:
            return "AirPlay"
        case .carplay:
            return "CarPlay"
        }
    }
}
import Foundation
import AVFoundation
import MediaPlayer
import Combine

class AudioPlayerService: NSObject, ObservableObject {
    static let shared = AudioPlayerService()
    
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentEpisode: Episode?
    @Published var playbackPosition: TimeInterval = 0
    private var _internalPlaybackPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var canSeekForward = true
    @Published var canSeekBackward = true
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var lastSaveTime: Date = Date()
    private let saveInterval: TimeInterval = 15.0 // Save progress every 15 seconds
    
    // Debouncing for UI updates to prevent view update conflicts
    private var updateWorkItem: DispatchWorkItem?
    private let updateDebounceInterval: TimeInterval = 0.1
    
    // Cache for prepared AVPlayerItems to reduce loading time (with size limit)
    // REAL MEMORY ISSUE: AVPlayerItems contain audio buffers and are heavy
    private var playerItemCache: [String: AVPlayerItem] = [:]
    private let cacheQueue = DispatchQueue(label: "player.cache", qos: .utility)
    private let maxCacheSize = 2 // Very limited - AVPlayerItems are memory-heavy
    
    private override init() {
        super.init()
        
        // Initialize crash prevention first
        CrashPreventionManager.shared.startCrashPrevention()
        
        // Initialize playback speed from saved value
        let storedSpeed = UserDefaults.standard.float(forKey: "playbackSpeed")
        playbackSpeed = storedSpeed == 0 ? 1.0 : storedSpeed
        
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotificationObservers()
        Task { @MainActor in
            restoreLastPlayingEpisode()
        }
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        // Use crash prevention manager for safe audio session setup
        // The .playback category alone is sufficient for most podcast apps.
        // It supports background audio, AirPlay, and Bluetooth devices automatically.
        // Adding specific options like .allowBluetooth can sometimes cause conflicts (OSStatus error -50).
        let success = CrashPreventionManager.shared.safeConfigureAudioSession(category: .playback)
        
        if !success {
            print("⚠️ Failed to configure audio session.")
        }
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
        
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            self?.seekForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
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
    
    @objc private func handleEpisodeDidEnd(_ notification: Notification) {
        // Check if the notification is for our current player item
        if let playerItem = notification.object as? AVPlayerItem,
           playerItem == player?.currentItem {
            
            // Mark current episode as played and reset playback position
            if let currentEpisode = currentEpisode {
                // Use EpisodeRepository to properly persist the played status
                Task { @MainActor in
                    try? await EpisodeRepository.shared.markEpisodeAsPlayed(currentEpisode.id)
                    
                    // Also reset the playback position to 0 for completed episodes
                    try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(currentEpisode.id, 0)])
                }
                
                // Update the local reference
                self.currentEpisode?.played = true
                self.currentEpisode?.playbackPosition = 0
            }
            
            // Play next episode in queue
            if isPlaying {
                // Check if there's a next episode in the queue
                Task { @MainActor in
                    let queueViewModel = QueueViewModel.shared
                    if let nextEpisode = queueViewModel.getNextEpisode() {
                        // Load and play the next episode
                        self.loadEpisode(nextEpisode)
                        self.play()
                        
                        // Remove the completed episode from queue
                        queueViewModel.removeCurrentEpisode()
                        
                        print("🎵 AudioPlayerService: Auto-playing next episode: \(nextEpisode.title)")
                    } else {
                        // No more episodes in queue, stop playback
                        self.stop()
                        print("🎵 AudioPlayerService: Queue completed, stopping playback")
                    }
                }
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
                  // Save current playback position before going to background
          if let currentEpisode = currentEpisode {
             Task { @MainActor in
                 try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(currentEpisode.id, _internalPlaybackPosition)])
             }
             updateQueuePosition(for: currentEpisode, position: _internalPlaybackPosition)
          }
        
        // Clear cache to free memory in background
        clearPlayerItemCache()
        
        // Only keep audio session active if we're actually playing
        if isPlaying {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("⚠️ Failed to keep audio session active in background: \(error)")
            }
        }
    }
    
    @objc private func appDidBecomeActive() {
        // Only reactivate audio session if we have a current episode and are playing
        if isPlaying && currentEpisode != nil {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("⚠️ Failed to reactivate audio session: \(error)")
            }
        }
        
        // Update UI with current playback state
        updateNowPlayingInfo()
    }
    
    @objc private func appWillTerminate() {
                  // Save current playback position and episode ID before app terminates
          if let currentEpisode = currentEpisode {
             Task { @MainActor in
                 try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(currentEpisode.id, _internalPlaybackPosition)])
             }
             updateQueuePosition(for: currentEpisode, position: _internalPlaybackPosition)
             saveLastPlayingEpisodeId(currentEpisode.id.uuidString)
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
                print("⚠️ Failed to deactivate audio session on termination: \(error)")
            }
            
            // Clear now playing info from control center
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    func loadEpisode(_ episode: Episode) {
        guard let audioURL = episode.audioURL else { return }
        
        // Set loading state on main actor to avoid threading issues
        Task { @MainActor in
            self.isLoading = true
            LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: true)
        }
        
        // Stop current playback
        pause()
        
        // Clean up existing time observer and player
        cleanupPlayer()
        
        // Update current episode
        currentEpisode = episode
        
        // Save the episode ID for restoration on app relaunch
        saveLastPlayingEpisodeId(episode.id.uuidString)
        
        // Check if we have a cached player item first
        if let cachedPlayerItem = playerItemCache[episode.id.uuidString] {
            // Use cached item for faster loading
            player = AVPlayer(playerItem: cachedPlayerItem)
            setupPlayerForEpisode(episode, playerItem: cachedPlayerItem)
        } else {
            // Create new player item
            let playerItem = AVPlayerItem(url: audioURL)
            player = AVPlayer(playerItem: playerItem)
            
            // Cache the item for future use
            cacheQueue.async { [weak self] in
                self?.playerItemCache[episode.id.uuidString] = playerItem
                // Clean cache if it gets too large
                if self?.playerItemCache.count ?? 0 > 5 {
                    self?.cleanupOldCacheItems()
                }
            }
            
            setupPlayerForEpisode(episode, playerItem: playerItem)
        }
    }
    
    private func setupPlayerForEpisode(_ episode: Episode, playerItem: AVPlayerItem) {
        // Observe player item status for loading completion using crash prevention
        CrashPreventionManager.shared.safeAddObserver(self, to: playerItem, forKeyPath: "status", options: [.new])

        // Set up time observer for the new player
        setupTimeObserver()
        applyPlaybackSpeed()
        
        // Set up end-of-playback notification for this specific player item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEpisodeDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Get duration and update UI when ready
        Task { @MainActor in
            if let asset = self.player?.currentItem?.asset {
                Task {
                    do {
                        let duration = try await asset.load(.duration)
                        if !duration.isIndefinite {
                            await MainActor.run {
                                self.duration = CMTimeGetSeconds(duration)
                                
                                                                  // Save duration to episode if it's not already set
                                  if episode.episodeDuration == 0 {
                                     // Note: Duration updates are not supported in EpisodeRepository
                                     // This functionality may need to be implemented differently
                                  }
                            }
                        }
                    } catch {
                        print("⚠️ Failed to load asset duration: \(error)")
                    }
                }
            }
            
            // Seek to saved position after player is ready
            if episode.playbackPosition > 0 {
                let seekTime = CMTime(seconds: episode.playbackPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                self.player?.seek(to: seekTime) { [weak self] _ in
                    Task { @MainActor in
                        // Set both playback positions after seek completes
                        self?.playbackPosition = episode.playbackPosition
                        self?._internalPlaybackPosition = episode.playbackPosition
                        self?.isLoading = false
                        LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
                        // Update now playing info after seeking to show correct position
                        self?.updateNowPlayingInfo()
                    }
                }
            } else {
                // Set both playback positions to 0 for new episodes
                self.playbackPosition = 0
                self._internalPlaybackPosition = 0
                self.isLoading = false
                LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
                // Update now playing info immediately since no seeking needed
                self.updateNowPlayingInfo()
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "status", let playerItem = object as? AVPlayerItem else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        // CRITICAL FIX: Execute immediately to prevent main thread queue buildup
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch playerItem.status {
            case .readyToPlay:
                self.handlePlayerReadyToPlay(playerItem)
            case .failed:
                self.handlePlayerFailed(playerItem)
            case .unknown:
                // Nothing to do here, but we've handled the case.
                break
            @unknown default:
                break
            }
        }
    }
    
    private func handlePlayerReadyToPlay(_ playerItem: AVPlayerItem) {
        isLoading = false
        if let episode = currentEpisode {
            LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
        }

        Task {
            do {
                let duration = try await playerItem.asset.load(.duration)
                if !duration.isIndefinite {
                    await MainActor.run {
                                                  self.duration = CMTimeGetSeconds(duration)
                          if let currentEpisode = self.currentEpisode, currentEpisode.episodeDuration == 0 {
                             // Note: Duration updates are not supported in EpisodeRepository
                             // This functionality may need to be implemented differently
                          }
                    }
                }
            } catch {
                print("⚠️ Failed to load asset duration: \(error)")
            }
        }
    }

    private func handlePlayerFailed(_ playerItem: AVPlayerItem) {
        isLoading = false
        if let episode = currentEpisode {
            LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
        }
        print("⚠️ Player item failed to load: \(playerItem.error?.localizedDescription ?? "Unknown error")")
    }
    
    func clearPlayerItemCache() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            let cacheCount = self.playerItemCache.count
            self.playerItemCache.removeAll()
            print("🧹 Cleared player item cache (\(cacheCount) items) to free memory")
        }
    }
    
    private func manageCacheSize() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.playerItemCache.count > self.maxCacheSize {
                // Remove oldest entries (simple FIFO approach)
                let keysToRemove = Array(self.playerItemCache.keys).prefix(self.playerItemCache.count - self.maxCacheSize)
                for key in keysToRemove {
                    self.playerItemCache.removeValue(forKey: key)
                }
                print("🧹 Trimmed player cache to \(self.maxCacheSize) items (memory management)")
            }
        }
    }
    
    private func cleanupOldCacheItems() {
        manageCacheSize()
    }
    
    /// Preload episodes for faster playback
    func preloadEpisodes(_ episodes: [Episode]) {
        cacheQueue.async { [weak self] in
            // MEMORY FIX: Only preload 1 episode since AVPlayerItems are memory-heavy
            for episode in episodes.prefix(1) { // Reduced from 3 to 1
                guard let audioURL = episode.audioURL,
                      self?.playerItemCache[episode.id.uuidString] == nil else { continue }
                
                let playerItem = AVPlayerItem(url: audioURL)
                self?.playerItemCache[episode.id.uuidString] = playerItem
                print("🎵 Preloaded player item for: \(episode.title)")
            }
        }
    }
    
    private func cleanupPlayer() {
        // Remove time observer from current player if it exists
        if let observer = timeObserver, let currentPlayer = player {
            currentPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Remove end-of-playback notification observer for current player item
        if let currentPlayerItem = player?.currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: currentPlayerItem
            )
            
            // Remove status observer safely using crash prevention manager
            CrashPreventionManager.shared.safeRemoveObserver(self, from: currentPlayerItem, forKeyPath: "status")
        }
        
        // Clear the player reference
        player = nil
    }
    
    private func setupTimeObserver() {
        // Ensure we have a player and no existing observer
        guard let player = player else { return }
        
        // Clean up any existing observer first
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Use a background queue for the time observer to avoid blocking the main thread
        let timeObserverQueue = DispatchQueue(label: "audio-time-observer", qos: .utility)
        
        // Add new observer to the current player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: timeObserverQueue
        ) { [weak self] time in
            let currentTime = CMTimeGetSeconds(time)
            self?.debouncedUpdatePlaybackPosition(currentTime)
        }
    }
    
    private func debouncedUpdatePlaybackPosition(_ currentTime: TimeInterval) {
        // Update internal position immediately (non-published)
        _internalPlaybackPosition = currentTime
        
        // Cancel any pending UI update
        updateWorkItem?.cancel()
        
        // Create new work item for UI updates only
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // CRITICAL FIX: Update published property immediately to prevent main thread blocking
            self.playbackPosition = self._internalPlaybackPosition
        }
        
        // Store the work item
        updateWorkItem = workItem
        
        // CRITICAL FIX: Execute immediately instead of scheduling to prevent main thread queue buildup
        DispatchQueue.main.async(execute: workItem)
        
        // Handle non-UI updates immediately on background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.handleProgressUpdates()
        }
    }
    
    private func handleProgressUpdates() {
        guard let episode = currentEpisode else { return }
        let currentPosition = _internalPlaybackPosition

        // Automatically mark episode as played when less than 5 seconds remain
        if !episode.played && duration > 0 && (duration - currentPosition) <= 5 {
                          // CRITICAL FIX: Execute immediately to prevent main thread queue buildup
              Task { @MainActor in
                 try? await EpisodeRepository.shared.markEpisodeAsPlayed(episode.id)
                 self.currentEpisode?.played = true
              }
        }
        
        // Debounced saving of playback position to avoid excessive writes
        if Date().timeIntervalSince(lastSaveTime) > saveInterval {
                          // CRITICAL FIX: Execute immediately to prevent main thread queue buildup
              Task { @MainActor in
                 try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(episode.id, currentPosition)])
              }
            lastSaveTime = Date()
        }
        
        // Note: Queue position updates removed from time observer to prevent view update conflicts
        // Queue positions will be updated when episodes are saved/loaded instead
        
        // Update now playing info (this is safe as it doesn't publish to SwiftUI)
        updateNowPlayingInfo()
    }
    
    private func updateQueuePosition(for episode: Episode, position: TimeInterval) {
        // CRITICAL FIX: Execute immediately to prevent main thread queue buildup
        DispatchQueue.main.async {
            if let queueViewModel = QueueViewModel.shared as? QueueViewModel,
               let index = queueViewModel.queuedEpisodes.firstIndex(where: { $0.id == episode.id }) {
                queueViewModel.queuedEpisodes[index].playbackPosition = position
            }
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
        
        getPodcast(for: episode) { podcast in
            if let podcast = podcast {
                nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
            }
            
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self._internalPlaybackPosition
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? self.playbackSpeed : 0.0
            
            let artworkURL = episode.artworkURL ?? podcast?.artworkURL
            
            if let artworkURL = artworkURL {
                self.loadArtwork(from: artworkURL) { artwork in
                    // CRITICAL FIX: Execute immediately to prevent main thread queue buildup
                    DispatchQueue.main.async {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                }
            } else {
                // Set info without artwork for immediate display
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        }
    }
    
    private func getPodcast(for episode: Episode, completion: @escaping (Podcast?) -> Void) {
        Task {
            let podcasts = await PodcastService.shared.loadPodcastsAsync()
            let matchingPodcast = podcasts.first { $0.id == episode.podcastID }
            completion(matchingPodcast)
        }
    }
    
    private func loadArtwork(from url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        ImageCache.shared.loadImage(from: url) { image in
            guard let image = image else {
                completion(nil)
                return
            }
            
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            completion(artwork)
        }
    }
    

    
    func play() {
        // Activate audio session safely before playing
        let audioSession = AVAudioSession.sharedInstance()
        if !audioSession.isOtherAudioPlaying {
            _ = CrashPreventionManager.shared.safeActivateAudioSession()
        }

        player?.play()
        applyPlaybackSpeed()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        
                  // Save current playback position when pausing
          if let currentEpisode = currentEpisode {
             Task { @MainActor in
                 try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(currentEpisode.id, _internalPlaybackPosition)])
             }
             // Update queue position when pausing (safe time to update)
             updateQueuePosition(for: currentEpisode, position: _internalPlaybackPosition)
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
    
    func seekForward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = min(duration, currentTime + 15.0)
        let seekTime = CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTime)
    }
    
    func seekBackward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = max(0, currentTime - 15.0)
        let seekTime = CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTime)
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let clampedTime = max(0, min(duration, time))
        let seekTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTime)
    }

    func updatePlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        UserDefaults.standard.set(speed, forKey: "playbackSpeed")
        applyPlaybackSpeed()
    }

    private func applyPlaybackSpeed() {
        guard let player = player else { return }
        player.rate = playbackSpeed
    }
    
    func stop() {
                  // Save current playback position before stopping
          if let currentEpisode = currentEpisode {
             Task { @MainActor in
                 try? await EpisodeRepository.shared.batchUpdateEpisodes([.updatePlaybackPosition(currentEpisode.id, _internalPlaybackPosition)])
             }
             updateQueuePosition(for: currentEpisode, position: _internalPlaybackPosition)
          }
        
        player?.pause()
        
        // Clean up player and time observer
        cleanupPlayer()
        
        currentEpisode = nil
        isPlaying = false
        playbackPosition = 0
        _internalPlaybackPosition = 0
        duration = 0
        
        // Deactivate audio session when completely stopping
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    // MARK: - Episode Persistence
    
    private func saveLastPlayingEpisodeId(_ episodeId: String) {
        UserDefaults.standard.set(episodeId, forKey: "lastPlayingEpisodeId")
    }
    
    private func getLastPlayingEpisodeId() -> String? {
        return UserDefaults.standard.string(forKey: "lastPlayingEpisodeId")
    }
    
    /// Manually restore the last playing episode (useful when auto-restore is disabled)
    @MainActor func manuallyRestoreLastEpisode() {
        guard let lastEpisodeId = getLastPlayingEpisodeId(),
              let episodeUUID = UUID(uuidString: lastEpisodeId) else {
            print("🎵 No previous episode to restore")
            return
        }
        
        // Get episode from cache service using async API
        Task {
            // We need to find the episode across all cached podcasts
            let allPodcasts = await PodcastService.shared.loadPodcastsAsync()
            var foundEpisode: Episode?
            
            for podcast in allPodcasts {
                if let episodes = await EpisodeCacheService.shared.getEpisodes(for: podcast.id) {
                    if let episode = episodes.first(where: { $0.id == episodeUUID }) {
                        foundEpisode = episode
                        break
                    }
                }
            }
            
            guard let episode = foundEpisode else {
                print("🎵 Episode not found in cache")
                return
            }
        
            if episode.playbackPosition > 0 {
                print("🎵 Manually restoring episode: \(episode.title) at position \(Int(episode.playbackPosition))s")
                await MainActor.run {
                    self.loadEpisode(episode)
                }
            } else {
                print("🎵 Episode \(episode.title) has no saved position, loading from beginning")
                await MainActor.run {
                    self.loadEpisode(episode)
                }
            }
        }
    }
    
    @MainActor private func restoreLastPlayingEpisode() {
        // Check if user has enabled auto-restore
        let autoRestoreEnabled = UserDefaults.standard.bool(forKey: "autoRestoreLastEpisode")
        
        guard autoRestoreEnabled else {
            print("🎵 Auto-restore disabled by user - not restoring last episode")
            return
        }
        
        guard let lastEpisodeId = getLastPlayingEpisodeId(),
              let episodeUUID = UUID(uuidString: lastEpisodeId) else {
            print("🎵 No previous episode to restore")
            return
        }
        
        // Get episode from cache service using async API
        Task {
            // We need to find the episode across all cached podcasts
            let allPodcasts = await PodcastService.shared.loadPodcastsAsync()
            var foundEpisode: Episode?
            
            for podcast in allPodcasts {
                if let episodes = await EpisodeCacheService.shared.getEpisodes(for: podcast.id) {
                    if let episode = episodes.first(where: { $0.id == episodeUUID }) {
                        foundEpisode = episode
                        break
                    }
                }
            }
            
            guard let episode = foundEpisode else {
                print("🎵 Episode not found in cache")
                return
            }
        
            // Only restore if there was a saved playback position (meaning it was actually being played)
            if episode.playbackPosition > 0 {
                print("🎵 Restoring episode: \(episode.title) at position \(Int(episode.playbackPosition))s")
                // Load the episode but don't start playing - user must manually resume
                await MainActor.run {
                    self.loadEpisode(episode)
                }
                print("🎵 Episode loaded but not playing - ready for manual resume")
            } else {
                print("🎵 Episode \(episode.title) has no saved position, not restoring")
            }
        }
    }
} 
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
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var canSeekForward = true
    @Published var canSeekBackward = true
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    // Cache for prepared AVPlayerItems to reduce loading time
    private var playerItemCache: [String: AVPlayerItem] = [:]
    private let cacheQueue = DispatchQueue(label: "player.cache", qos: .utility)
    
    private override init() {
        super.init()
        
        // Initialize playback speed from saved value
        let storedSpeed = UserDefaults.standard.float(forKey: "playbackSpeed")
        playbackSpeed = storedSpeed == 0 ? 1.0 : storedSpeed
        
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotificationObservers()
        restoreLastPlayingEpisode()
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure audio session for background playback
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
            )
            
            // Only activate when we actually need to play audio
            // Don't activate immediately on app launch
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
            
            // Fallback to basic playback category without options
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            } catch {
                print("❌ Failed to set even basic audio session category: \(error)")
            }
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
                // Use EpisodeViewModel to properly persist the played status
                EpisodeViewModel.shared.markEpisodeAsPlayed(currentEpisode, played: true)
                
                // Also reset the playback position to 0 for completed episodes
                EpisodeViewModel.shared.updatePlaybackPosition(for: currentEpisode, position: 0)
                
                // Update the local reference
                self.currentEpisode?.played = true
                self.currentEpisode?.playbackPosition = 0
            }
            
            // Reset local playback position to 0 for the finished episode
            playbackPosition = 0
            
            // Play next episode in queue
            QueueViewModel.shared.playNextEpisode()
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Save current playback position before going to background
        if let currentEpisode = currentEpisode {
            EpisodeViewModel.shared.updatePlaybackPosition(for: currentEpisode, position: playbackPosition)
        }
        
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
            EpisodeViewModel.shared.updatePlaybackPosition(for: currentEpisode, position: playbackPosition)
            saveLastPlayingEpisodeId(currentEpisode.id.uuidString)
        }
    }
    
    func loadEpisode(_ episode: Episode) {
        guard let audioURL = episode.audioURL else { return }
        
        // Set loading state immediately
        DispatchQueue.main.async {
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
        // Observe player item status for loading completion
        playerItem.addObserver(self, forKeyPath: "status", options: [.new], context: nil)

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
        DispatchQueue.main.async {
            if let asset = self.player?.currentItem?.asset {
                let duration = asset.duration
                if !duration.isIndefinite {
                    self.duration = CMTimeGetSeconds(duration)
                    
                    // Save duration to episode if it's not already set
                    if episode.episodeDuration == 0 {
                        EpisodeViewModel.shared.updateEpisodeDuration(episode, duration: self.duration)
                    }
                }
            }
            
            // Seek to saved position after player is ready
            if episode.playbackPosition > 0 {
                let seekTime = CMTime(seconds: episode.playbackPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                self.player?.seek(to: seekTime) { [weak self] _ in
                    DispatchQueue.main.async {
                        // Set the playback position property after seek completes to ensure UI shows correct position
                        self?.playbackPosition = episode.playbackPosition
                        self?.isLoading = false
                        LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
                        // Update now playing info after seeking to show correct position
                        self?.updateNowPlayingInfo()
                    }
                }
            } else {
                // Set playback position to 0 for new episodes
                self.playbackPosition = 0
                self.isLoading = false
                LoadingStateManager.shared.setEpisodeLoading(episode.id, isLoading: false)
                // Update now playing info immediately since no seeking needed
                self.updateNowPlayingInfo()
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let playerItem = object as? AVPlayerItem {
            DispatchQueue.main.async {
                switch playerItem.status {
                case .readyToPlay:
                    self.isLoading = false
                    if let currentEpisode = self.currentEpisode {
                        LoadingStateManager.shared.setEpisodeLoading(currentEpisode.id, isLoading: false)
                    }
                    let duration = playerItem.asset.duration
                    if !duration.isIndefinite {
                        self.duration = CMTimeGetSeconds(duration)
                        
                        // Save duration to episode if it's not already set
                        if let currentEpisode = self.currentEpisode, currentEpisode.episodeDuration == 0 {
                            EpisodeViewModel.shared.updateEpisodeDuration(currentEpisode, duration: self.duration)
                        }
                    }
                case .failed:
                    self.isLoading = false
                    if let currentEpisode = self.currentEpisode {
                        LoadingStateManager.shared.setEpisodeLoading(currentEpisode.id, isLoading: false)
                    }
                    print("⚠️ Player item failed to load: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func cleanupOldCacheItems() {
        // Keep only the 3 most recently used items
        let maxCacheSize = 3
        if playerItemCache.count > maxCacheSize {
            let keysToRemove = Array(playerItemCache.keys.prefix(playerItemCache.count - maxCacheSize))
            for key in keysToRemove {
                playerItemCache.removeValue(forKey: key)
            }
        }
    }
    
    /// Preload episodes for faster playback
    func preloadEpisodes(_ episodes: [Episode]) {
        cacheQueue.async { [weak self] in
            for episode in episodes.prefix(3) { // Only preload first 3
                guard let audioURL = episode.audioURL,
                      self?.playerItemCache[episode.id.uuidString] == nil else { continue }
                
                let playerItem = AVPlayerItem(url: audioURL)
                self?.playerItemCache[episode.id.uuidString] = playerItem
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
            
            // Remove status observer (wrap in try-catch in case observer wasn't added)
            currentPlayerItem.removeObserver(self, forKeyPath: "status")
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
        
        // Add new observer to the current player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] time in
            self?.playbackPosition = CMTimeGetSeconds(time)
            self?.updatePlaybackProgress()
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else { return }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
        
        // Add podcast title as artist if available
        if let podcast = getPodcast(for: episode) {
            nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
        }
        
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0
        
        // Try episode artwork first, then podcast artwork, then placeholder
        let artworkURL = episode.artworkURL ?? getPodcast(for: episode)?.artworkURL
        
        if let artworkURL = artworkURL {
            loadArtwork(from: artworkURL) { artwork in
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
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func loadArtwork(from url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        // Create a URL session with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0 // 10 second timeout
        let session = URLSession(configuration: config)
        
        session.dataTask(with: url) { data, response, error in
            // Check for errors
            if let error = error {
                print("⚠️ Failed to load artwork from \(url): \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            // Check for valid data and create image
            guard let data = data, 
                  let image = UIImage(data: data) else {
                print("⚠️ Invalid artwork data from \(url)")
                completion(nil)
                return
            }
            
            // Ensure image has reasonable size (not too large for memory)
            let maxSize: CGFloat = 600
            let finalImage: UIImage
            
            if max(image.size.width, image.size.height) > maxSize {
                // Resize image to prevent memory issues
                let aspectRatio = image.size.width / image.size.height
                let newSize: CGSize
                
                if image.size.width > image.size.height {
                    newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
                } else {
                    newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
                }
                
                UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
            } else {
                finalImage = image
            }
            
            // Create artwork with proper bounds
            let artwork = MPMediaItemArtwork(boundsSize: finalImage.size) { _ in finalImage }
            completion(artwork)
        }.resume()
    }
    
    private func updatePlaybackProgress() {
        guard let episode = currentEpisode else { return }

        // Automatically mark episode as played when less than 5 seconds remain
        if !episode.played && duration > 0 && (duration - playbackPosition) <= 5 {
            EpisodeViewModel.shared.markEpisodeAsPlayed(episode, played: true)
            currentEpisode?.played = true
        }
        
        // Update episode in queue - ensure this happens on main thread since we're updating @Published properties
        DispatchQueue.main.async {
            if let queueViewModel = QueueViewModel.shared as QueueViewModel?,
               let index = queueViewModel.queue.firstIndex(where: { $0.id == episode.id }) {
                queueViewModel.queue[index].playbackPosition = self.playbackPosition
                queueViewModel.saveQueue()
            }
        }
        
        // Update now playing info
        updateNowPlayingInfo()
    }
    
    func play() {
        // Activate audio session before playing (only if not already active)
        let audioSession = AVAudioSession.sharedInstance()
        if !audioSession.isOtherAudioPlaying {
            do {
                try audioSession.setActive(true)
            } catch {
                print("⚠️ Failed to activate audio session: \(error)")
            }
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
            EpisodeViewModel.shared.updatePlaybackPosition(for: currentEpisode, position: playbackPosition)
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
            EpisodeViewModel.shared.updatePlaybackPosition(for: currentEpisode, position: playbackPosition)
        }
        
        player?.pause()
        
        // Clean up player and time observer
        cleanupPlayer()
        
        currentEpisode = nil
        isPlaying = false
        playbackPosition = 0
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
    
    private func restoreLastPlayingEpisode() {
        guard let lastEpisodeId = getLastPlayingEpisodeId(),
              let episode = EpisodeViewModel.shared.findEpisode(by: lastEpisodeId) else {
            return
        }
        
        // Only restore if there was a saved playback position (meaning it was actually being played)
        if episode.playbackPosition > 0 {
            // Load the episode but don't start playing
            loadEpisode(episode)
        }
    }
} 
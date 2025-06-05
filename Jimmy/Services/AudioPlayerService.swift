import Foundation
import AVFoundation
import MediaPlayer
import WidgetKit

class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()
    
    @Published var isPlaying = false
    @Published var currentEpisode: Episode?
    @Published var playbackPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    private init() {
        setupAudioSession()
        setupRemoteTransportControls()
        setupNotificationObservers()
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
            
            // Mark current episode as played
            if let currentEpisode = currentEpisode {
                var updatedEpisode = currentEpisode
                updatedEpisode.played = true
                
                // Update episode in queue
                if let queueViewModel = QueueViewModel.shared as QueueViewModel?,
                   let index = queueViewModel.queue.firstIndex(where: { $0.id == updatedEpisode.id }) {
                    queueViewModel.queue[index] = updatedEpisode
                }
            }
            
            // Reset playback position to 0 for the finished episode
            playbackPosition = 0
            
            // Play next episode in queue
            QueueViewModel.shared.playNextEpisode()
        }
    }
    
    @objc private func appDidEnterBackground() {
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
        updateWidgetData()
    }
    
    func loadEpisode(_ episode: Episode) {
        guard let audioURL = episode.audioURL else { return }
        
        // Stop current playback
        pause()
        
        // Clean up existing time observer and player
        cleanupPlayer()
        
        // Update current episode
        currentEpisode = episode
        
        // Create player item
        let playerItem = AVPlayerItem(url: audioURL)
        player = AVPlayer(playerItem: playerItem)
        
        // Seek to saved position
        if episode.playbackPosition > 0 {
            let seekTime = CMTime(seconds: episode.playbackPosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: seekTime)
        }
        
        // Set up time observer for the new player
        setupTimeObserver()
        
        // Set up end-of-playback notification for this specific player item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEpisodeDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        // Get duration first
        if let duration = player?.currentItem?.asset.duration {
            self.duration = CMTimeGetSeconds(duration)
        }
        
        // Update now playing info (this will load artwork)
        updateNowPlayingInfo()
        
        // Update widget data
        updateWidgetData()
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
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
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
        
        // Update episode in queue
        if let queueViewModel = QueueViewModel.shared as QueueViewModel?,
           let index = queueViewModel.queue.firstIndex(where: { $0.id == episode.id }) {
            queueViewModel.queue[index].playbackPosition = playbackPosition
            queueViewModel.saveQueue()
        }
        
        // Update now playing info
        updateNowPlayingInfo()
        
        // Update widget data
        updateWidgetData()
    }
    
    func play() {
        // Activate audio session before playing
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Failed to activate audio session: \(error)")
        }
        
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
        updateWidgetData()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        updateWidgetData()
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
        updateWidgetData()
    }
    
    func seekBackward() {
        guard let player = player else { return }
        let currentTime = CMTimeGetSeconds(player.currentTime())
        let newTime = max(0, currentTime - 15.0)
        let seekTime = CMTime(seconds: newTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTime)
        updateWidgetData()
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let clampedTime = max(0, min(duration, time))
        let seekTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: seekTime)
        updateWidgetData()
    }
    
    func stop() {
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
        
        // Update widget data
        updateWidgetData()
    }
    
    // MARK: - Widget Data Updates
    private func updateWidgetData() {
        let widgetData = WidgetDataService.shared
        widgetData.saveCurrentEpisode(currentEpisode)
        widgetData.savePlaybackState(isPlaying: isPlaying, position: playbackPosition, duration: duration)
        widgetData.notifyWidgetUpdate()

        // Send playback info to Apple Watch
        WatchConnectivityService.shared.sendPlaybackUpdate(
            episode: currentEpisode,
            isPlaying: isPlaying,
            position: playbackPosition,
            duration: duration
        )
        
        // Reload widget timelines
        WidgetCenter.shared.reloadTimelines(ofKind: "JimmyWidgetExtension")
    }
} 
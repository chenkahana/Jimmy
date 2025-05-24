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
            // Configure audio session for background playback
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
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
    
    @objc private func appDidEnterBackground() {
        // Ensure audio session remains active in background
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to keep audio session active in background: \(error)")
        }
    }
    
    @objc private func appDidBecomeActive() {
        // Refresh audio session when app becomes active
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to reactivate audio session: \(error)")
        }
        
        // Update UI with current playback state
        updateNowPlayingInfo()
        updateWidgetData()
    }
    
    func loadEpisode(_ episode: Episode) {
        guard let audioURL = episode.audioURL else { return }
        
        // Stop current playback
        pause()
        
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
        
        // Set up time observer
        setupTimeObserver()
        
        // Update now playing info
        updateNowPlayingInfo()
        
        // Get duration
        if let duration = player?.currentItem?.asset.duration {
            self.duration = CMTimeGetSeconds(duration)
        }
        
        // Update widget data
        updateWidgetData()
    }
    
    private func setupTimeObserver() {
        // Remove existing observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        
        // Add new observer
        timeObserver = player?.addPeriodicTimeObserver(
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
        nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title.cleanedEpisodeTitle
        
        // Add podcast title as artist if available
        if let podcast = getPodcast(for: episode) {
            nowPlayingInfo[MPMediaItemPropertyArtist] = podcast.title
        }
        
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackPosition
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // Load artwork if available
        if let artworkURL = episode.artworkURL {
            loadArtwork(from: artworkURL) { artwork in
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func loadArtwork(from url: URL, completion: @escaping (MPMediaItemArtwork?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                completion(nil)
                return
            }
            
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                completion(artwork)
            }
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
        player = nil
        currentEpisode = nil
        isPlaying = false
        playbackPosition = 0
        duration = 0
        
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
        
        // Reload widget timelines
        WidgetCenter.shared.reloadTimelines(ofKind: "JimmyWidgetExtension")
    }
} 
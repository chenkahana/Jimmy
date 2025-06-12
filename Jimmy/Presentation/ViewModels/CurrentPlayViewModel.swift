import Foundation
import Combine
import AVFoundation

/// ViewModel for CurrentPlay functionality following MVVM patterns
@MainActor
class CurrentPlayViewModel: ObservableObject {
    static let shared = CurrentPlayViewModel()
    
    // MARK: - Published Properties
    @Published var isDownloading = false
    @Published var currentAudioRoute = ""
    @Published var showingEpisodeDetails = false
    @Published var currentOutputDevice: AudioOutputDevice = .speaker
    
    // MARK: - Dependencies
    private let queueViewModel: QueueViewModel
    private let audioPlayerService: AudioPlayerService
    private let podcastService: PodcastService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var currentPlayingEpisode: Episode? {
        return audioPlayerService.currentEpisode ?? queueViewModel.queuedEpisodes.first { $0.playbackPosition > 0 && !$0.played }
    }
    
    // MARK: - Initialization
    private init(
        queueViewModel: QueueViewModel = .shared,
        audioPlayerService: AudioPlayerService = .shared,
        podcastService: PodcastService = .shared
    ) {
        self.queueViewModel = queueViewModel
        self.audioPlayerService = audioPlayerService
        self.podcastService = podcastService
        
        setupBindings()
        updateCurrentAudioRoute()
        updateCurrentOutputDevice()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen for audio route changes
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateCurrentAudioRoute()
                    self?.updateCurrentOutputDevice()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateCurrentAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        currentAudioRoute = session.currentRoute.outputs.first?.portName ?? "Unknown"
    }
    
    private func updateCurrentOutputDevice() {
        currentOutputDevice = getCurrentAudioOutputDevice()
    }
    
    private func getCurrentAudioOutputDevice() -> AudioOutputDevice {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else {
            return .speaker
        }
        
        switch output.portType {
        case .builtInSpeaker:
            return .speaker
        case .headphones:
            return .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth(name: output.portName)
        case .airPlay:
            return .airplay(name: output.portName)
        case .HDMI:
            return .hdmi(name: output.portName)
        case .lineOut:
            return .wired(name: output.portName)
        default:
            return .speaker
        }
    }
    
    // MARK: - Public Methods
    func getPodcast(for episode: Episode) -> Podcast? {
        return podcastService.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    func downloadEpisode(_ episode: Episode) async {
        isDownloading = true
        defer { isDownloading = false }
        
        await withCheckedContinuation { continuation in
            podcastService.downloadEpisode(episode) { url in
                continuation.resume()
            }
        }
    }
    
    func playPauseCurrentEpisode() {
        guard let currentEpisode = currentPlayingEpisode else { return }
        
        if audioPlayerService.currentEpisode?.id == currentEpisode.id {
            audioPlayerService.togglePlayPause()
        } else {
            audioPlayerService.loadEpisode(currentEpisode)
            audioPlayerService.play()
        }
    }
    
    func seekBackward() {
        audioPlayerService.seekBackward()
    }
    
    func seekForward() {
        audioPlayerService.seekForward()
    }
    
    func seek(to time: TimeInterval) {
        audioPlayerService.seek(to: time)
    }
    
    func showEpisodeDetails() {
        showingEpisodeDetails = true
    }
    
    func hideEpisodeDetails() {
        showingEpisodeDetails = false
    }
}

// MARK: - Supporting Types
enum AudioOutputDevice: Hashable {
    case speaker
    case headphones
    case bluetooth(name: String)
    case airplay(name: String)
    case hdmi(name: String)
    case wired(name: String)
    
    var displayName: String {
        switch self {
        case .speaker:
            return "iPhone Speaker"
        case .headphones:
            return "Headphones"
        case .bluetooth(let name):
            return name
        case .airplay(let name):
            return name
        case .hdmi(let name):
            return name
        case .wired(let name):
            return name
        }
    }
    
    var icon: String {
        switch self {
        case .speaker:
            return "speaker.wave.3"
        case .headphones:
            return "headphones"
        case .bluetooth:
            return "airpods"
        case .airplay:
            return "airplayvideo"
        case .hdmi:
            return "tv"
        case .wired:
            return "headphones"
        }
    }
} 
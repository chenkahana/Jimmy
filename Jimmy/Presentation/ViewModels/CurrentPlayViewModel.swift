import Foundation
import Combine
import AVFoundation

struct PlaybackViewState: Equatable {
    var isDownloading = false
    var currentAudioRoute = ""
    var currentOutputDevice: AudioOutputDevice = .speaker
    var showingEpisodeDetails = false
    var showingOptionsMenu = false
}

/// ViewModel for CurrentPlay functionality following MVVM patterns
@MainActor
class CurrentPlayViewModel: ObservableObject {
    static let shared = CurrentPlayViewModel()
    
    // MARK: - Published Properties
    @Published var isDownloading = false {
        didSet {
            state.isDownloading = isDownloading
        }
    }
    @Published var currentAudioRoute = "" {
        didSet {
            state.currentAudioRoute = currentAudioRoute
        }
    }
    @Published var showingEpisodeDetails = false {
        didSet {
            state.showingEpisodeDetails = showingEpisodeDetails
        }
    }
    @Published var currentOutputDevice: AudioOutputDevice = .speaker {
        didSet {
            state.currentOutputDevice = currentOutputDevice
        }
    }
    @Published var showingOptionsMenu = false {
        didSet {
            state.showingOptionsMenu = showingOptionsMenu
        }
    }
    @Published private(set) var state = PlaybackViewState()
    
    // MARK: - Dependencies
    private let audioPlayerService: AudioPlayerService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    var currentPlayingEpisode: Episode? {
        audioPlayerService.currentEpisode
    }
    
    var routeIcon: String {
        audioPlayerService.currentAudioRoute.iconName
    }
    
    // MARK: - Initialization
    private init(
        audioPlayerService: AudioPlayerService = .shared
    ) {
        self.audioPlayerService = audioPlayerService
        
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
                self?.updateCurrentAudioRoute()
                self?.updateCurrentOutputDevice()
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
        PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    func downloadEpisode(_ episode: Episode) async {
        isDownloading = true
        defer { isDownloading = false }
        
        await withCheckedContinuation { continuation in
            // This method is no longer used in the new implementation
            continuation.resume()
        }
    }
    
    func playPauseCurrentEpisode() {
        audioPlayerService.togglePlayPause()
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
    
    func skipForward() {
        audioPlayerService.seekForward()
    }
    
    func skipBackward() {
        audioPlayerService.seekBackward()
    }
    
    func showOptionsMenu() {
        showingOptionsMenu = true
    }
    
    func shareEpisode() {
        // Share functionality will be handled in the view
        showingOptionsMenu = false
    }
    
    func addToQueue() {
        guard let episode = currentPlayingEpisode else { return }
        Task {
            try? await QueueViewModel.shared.addEpisode(episode)
        }
        showingOptionsMenu = false
    }
    
    func goToShow() {
        // Navigation will be handled in the view
        showingOptionsMenu = false
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

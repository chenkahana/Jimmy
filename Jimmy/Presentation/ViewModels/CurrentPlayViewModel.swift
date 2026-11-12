import Foundation
import JimmyKit
import Combine
import AVFoundation
import Observation

struct PlaybackViewState: Equatable {
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

    /// Mirrors `AppModel.current?.playback.currentEpisode`, converted to the old richer `Episode`
    /// type this view model's callers (e.g. `ExpandedNowPlayingView`) still expect.
    @Published private(set) var currentPlayingEpisode: Episode?

    // MARK: - Dependencies
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties
    var routeIcon: String {
        currentOutputDevice.icon
    }

    // MARK: - Initialization
    private init() {
        setupBindings()
        updateCurrentAudioRoute()
        updateCurrentOutputDevice()
        startObservingPlayback()
    }

    // MARK: - Private Methods
    private func setupBindings() {
        // Listen for audio route changes
        // AVAudioSession posts route changes on a background thread.
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCurrentAudioRoute()
                self?.updateCurrentOutputDevice()
            }
            .store(in: &cancellables)
    }

    /// `Playback` is `@Observable`, not an `ObservableObject` this Combine-based view model can
    /// subscribe to — track `currentEpisode` and re-register on every change instead.
    private func startObservingPlayback() {
        withObservationTracking {
            currentPlayingEpisode = AppModel.current?.playback?.currentEpisode?.asLegacyEpisode()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.startObservingPlayback()
            }
        }
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
        AppModel.current?.podcasts.first { $0.id == episode.podcastID }?.asLegacyPodcast()
    }
    
    /// `episode`'s download lifecycle state, `nil` if nothing has ever started downloading it.
    func downloadState(for episode: Episode) -> JimmyKit.DownloadState? {
        AppModel.current?.downloadState(for: episode.id)
    }

    /// `episode`'s download progress (0...1), `nil` while it isn't downloading.
    func downloadProgress(for episode: Episode) -> Double? {
        AppModel.current?.downloads?.progress[episode.id]
    }

    func downloadEpisode(_ episode: Episode) {
        AppModel.current?.download(episode.asPlaybackEpisode())
    }

    func cancelDownload(_ episode: Episode) {
        AppModel.current?.cancelDownload(episode.id)
    }

    func deleteDownload(_ episode: Episode) {
        AppModel.current?.deleteDownload(episode.id)
    }
    
    func playPauseCurrentEpisode() {
        Task { await AppModel.current?.playback?.togglePlayPause() }
    }

    func seekBackward() {
        Task { await AppModel.current?.playback?.skipBackward() }
    }

    func seekForward() {
        Task { await AppModel.current?.playback?.skipForward() }
    }

    func seek(to time: TimeInterval) {
        Task { await AppModel.current?.playback?.seek(to: time) }
    }
    
    func showEpisodeDetails() {
        showingEpisodeDetails = true
    }
    
    func hideEpisodeDetails() {
        showingEpisodeDetails = false
    }
    
    func skipForward() {
        Task { await AppModel.current?.playback?.skipForward() }
    }

    func skipBackward() {
        Task { await AppModel.current?.playback?.skipBackward() }
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
            await AppModel.current?.enqueue(episode.id)
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

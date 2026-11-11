import Foundation
import Combine
import AVFoundation

/// ViewModel for Audio Player functionality following MVVM patterns
@MainActor
class AudioPlayerViewModel: ObservableObject {
    static let shared = AudioPlayerViewModel()
    // MARK: - Published Properties
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var currentEpisode: Episode?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var playbackProgress: Double = 0.0
    @Published var remainingTime: TimeInterval = 0
    @Published var isBuffering: Bool = false
    
    // MARK: - Private Properties
    private let audioPlayerService: AudioPlayerService
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    
    // MARK: - Initialization
    private init(audioPlayerService: AudioPlayerService = .shared) {
        self.audioPlayerService = audioPlayerService
        setupBindings()
        setupProgressTimer()
    }
    
    deinit {
        cancellables.removeAll()
        progressTimer?.invalidate()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Bind to audio service state
        audioPlayerService.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        
        audioPlayerService.$playbackPosition
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentTime, on: self)
            .store(in: &cancellables)
        
        audioPlayerService.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: \.duration, on: self)
            .store(in: &cancellables)
        
        audioPlayerService.$currentEpisode
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentEpisode, on: self)
            .store(in: &cancellables)
        
        audioPlayerService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        // Calculate derived properties
        Publishers.CombineLatest($currentTime, $duration)
            .map { currentTime, duration in
                guard duration > 0 else { return 0.0 }
                return currentTime / duration
            }
            .assign(to: \.playbackProgress, on: self)
            .store(in: &cancellables)
        
        Publishers.CombineLatest($currentTime, $duration)
            .map { currentTime, duration in
                max(0, duration - currentTime)
            }
            .assign(to: \.remainingTime, on: self)
            .store(in: &cancellables)
    }
    
    private func setupProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }
    
    private func updateProgress() {
        currentTime = audioPlayerService.playbackPosition
        duration = audioPlayerService.duration
    }
    
    // MARK: - Public Methods
    func play() async {
        audioPlayerService.play()
        errorMessage = nil
    }
    
    func pause() {
        audioPlayerService.pause()
    }
    
    func togglePlayPause() async {
        if isPlaying {
            pause()
        } else {
            await play()
        }
    }
    
    func playEpisode(_ episode: Episode) async {
        isLoading = true
        errorMessage = nil
        
        audioPlayerService.loadEpisode(episode)
        audioPlayerService.play()
        
        isLoading = false
    }
    
    func seek(to time: TimeInterval) async {
        audioPlayerService.seek(to: time)
        errorMessage = nil
    }
    
    func seekForward(_ seconds: TimeInterval = 30) async {
        let newTime = min(currentTime + seconds, duration)
        await seek(to: newTime)
    }
    
    func seekBackward(_ seconds: TimeInterval = 15) async {
        let newTime = max(currentTime - seconds, 0)
        await seek(to: newTime)
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        audioPlayerService.updatePlaybackSpeed(rate)
    }
    
    func setVolume(_ volume: Float) {
        self.volume = volume
        // Volume control is handled by system volume controls
    }
    
    func stop() {
        audioPlayerService.stop()
    }
    
    func skipToNext() async {
        // Skip functionality would need to be implemented with queue management
        audioPlayerService.seekForward()
        errorMessage = nil
    }
    
    func skipToPrevious() async {
        // Skip functionality would need to be implemented with queue management  
        audioPlayerService.seekBackward()
        errorMessage = nil
    }
    
    // MARK: - Computed Properties
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }
    
    var formattedDuration: String {
        formatTime(duration)
    }
    
    var formattedRemainingTime: String {
        formatTime(remainingTime)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
} 
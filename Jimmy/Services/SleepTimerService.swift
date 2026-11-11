import Foundation
import Combine
import AVFoundation

/// Sleep timer service with countdown, volume fade-out, and background resilience.
/// Uses absolute endDate so the timer survives app backgrounding.
@MainActor
final class SleepTimerService: ObservableObject {
    static let shared = SleepTimerService()

    // MARK: - Public State
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var selectedPreset: SleepTimerPreset?

    // MARK: - Presets
    enum SleepTimerPreset: Identifiable, CaseIterable {
        case minutes5, minutes15, minutes30, minutes45, minutes60, endOfEpisode

        var id: String { label }

        var label: String {
            switch self {
            case .minutes5: return "5 min"
            case .minutes15: return "15 min"
            case .minutes30: return "30 min"
            case .minutes45: return "45 min"
            case .minutes60: return "60 min"
            case .endOfEpisode: return "End of Episode"
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .minutes5: return 5 * 60
            case .minutes15: return 15 * 60
            case .minutes30: return 30 * 60
            case .minutes45: return 45 * 60
            case .minutes60: return 60 * 60
            case .endOfEpisode: return nil // calculated dynamically
            }
        }
    }

    // MARK: - Private
    private var endDate: Date?
    private var timer: Timer?
    private var originalVolume: Float = 1.0
    private let fadeOutDuration: TimeInterval = 30
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Listen for episode completion to handle "end of episode" preset
        NotificationCenter.default.publisher(for: .episodeStatusUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.isActive, self.selectedPreset == .endOfEpisode else { return }
                // The episode ended — stop playback
                self.timerFired()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API

    func start(preset: SleepTimerPreset) {
        cancel()
        selectedPreset = preset
        let audioPlayer = AudioPlayerService.shared

        if preset == .endOfEpisode {
            // Will stop at the end of the current episode naturally via notification
            // Calculate remaining time for countdown display
            let remaining = audioPlayer.duration - audioPlayer.playbackPosition
            endDate = Date().addingTimeInterval(max(remaining, 0))
        } else if let seconds = preset.seconds {
            endDate = Date().addingTimeInterval(seconds)
        }

        originalVolume = audioPlayer.volume
        isActive = true
        startCountdownTimer()
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        isActive = false
        remainingSeconds = 0
        selectedPreset = nil
        // Restore original volume
        AudioPlayerService.shared.setVolume(originalVolume)
    }

    func extend(by seconds: TimeInterval) {
        guard isActive, let current = endDate else { return }
        endDate = current.addingTimeInterval(seconds)
    }

    // MARK: - Private

    private func startCountdownTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let endDate = endDate else { return }
        let remaining = endDate.timeIntervalSinceNow

        if remaining <= 0 {
            timerFired()
            return
        }

        remainingSeconds = remaining

        // Fade out volume over the last 30 seconds
        if remaining <= fadeOutDuration {
            let fraction = Float(remaining / fadeOutDuration)
            AudioPlayerService.shared.setVolume(originalVolume * fraction)
        }
    }

    private func timerFired() {
        AudioPlayerService.shared.pause()
        AudioPlayerService.shared.setVolume(originalVolume)
        cancel()
    }

    /// Formatted remaining time string
    var formattedRemaining: String {
        let total = Int(remainingSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

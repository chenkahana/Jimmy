import Foundation
@testable import JimmyKit

/// A `PlayerEngine` double. Tests drive it directly via `simulate*` methods instead of waiting on
/// real `AVPlayer` timing.
final class FakePlayerEngine: PlayerEngine {
    var onTimeUpdate: ((TimeInterval) async -> Void)?
    var onDurationAvailable: ((TimeInterval) -> Void)?
    var onEndOfItem: (() async -> Void)?

    var rate: Float = 1.0
    var volume: Float = 1.0
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval?

    private(set) var loadedURLs: [URL] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekedTimes: [TimeInterval] = []
    private(set) var isPlaying = false

    func load(url: URL) {
        loadedURLs.append(url)
        currentTime = 0
        duration = nil
    }

    func play() {
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        seekedTimes.append(time)
        currentTime = time
    }

    // MARK: - Test driving

    func simulateTimeUpdate(_ time: TimeInterval) async {
        currentTime = time
        await onTimeUpdate?(time)
    }

    func simulateDurationAvailable(_ duration: TimeInterval) {
        self.duration = duration
        onDurationAvailable?(duration)
    }

    func simulateEndOfItem() async {
        await onEndOfItem?()
    }
}

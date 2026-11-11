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
    private(set) var loadedStartPositions: [TimeInterval] = []
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var seekedTimes: [TimeInterval] = []
    private(set) var isPlaying = false

    /// When true, a `load` leaves the engine not-ready until a test calls `simulateBecomesReady()`,
    /// instead of becoming ready immediately — mirroring `AVPlayerEngine` deferring the restore
    /// seek, and any `onTimeUpdate` ticks, until `AVPlayerItem.status == .readyToPlay`. Defaults to
    /// false so existing tests that don't care about readiness timing are unaffected.
    var becomesReadySlowly = false
    private(set) var isReady = true
    private var pendingStartPosition: TimeInterval = 0
    /// Mirrors `AVPlayerEngine.play()` deferring the actual `player.play()` until the item is
    /// ready: a `play()` call that arrives first is remembered and applied once ready, rather than
    /// taking effect (and bumping `playCallCount`) immediately.
    private var pendingPlayRequested = false

    func load(url: URL, startPosition: TimeInterval) {
        loadedURLs.append(url)
        loadedStartPositions.append(startPosition)
        currentTime = 0
        duration = nil
        pendingStartPosition = startPosition
        pendingPlayRequested = false
        if becomesReadySlowly {
            isReady = false
        } else {
            applyReady()
        }
    }

    private func applyReady() {
        isReady = true
        if pendingStartPosition > 0 {
            seekedTimes.append(pendingStartPosition)
            currentTime = pendingStartPosition
        }
        if pendingPlayRequested {
            pendingPlayRequested = false
            playCallCount += 1
            isPlaying = true
        }
    }

    /// Test-driving: completes a slow `load`, applying the deferred restore seek and any `play()`
    /// that arrived first — call after asserting nothing was saved/reported/played yet, to
    /// simulate the item becoming ready late.
    func simulateBecomesReady() {
        applyReady()
    }

    func play() {
        guard isReady else {
            pendingPlayRequested = true
            return
        }
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
        guard isReady else { return }
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

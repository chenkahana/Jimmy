import Foundation
import AVFoundation

/// The real `PlayerEngine`, backed by `AVPlayer`. Available on every platform JimmyKit targets
/// (AVFoundation ships on iOS, watchOS, and macOS), so it needs no `#if os(...)` guard — unlike
/// the lock-screen/remote-command/audio-session integrations, which are iOS/MediaPlayer-only.
public final class AVPlayerEngine: PlayerEngine {
    public var onTimeUpdate: ((TimeInterval) async -> Void)?
    public var onDurationAvailable: ((TimeInterval) -> Void)?
    public var onEndOfItem: (() async -> Void)?

    public var rate: Float = 1.0 {
        didSet {
            // `AVPlayer.play()` resets `rate` to `defaultRate` on iOS 16+, so a custom speed only
            // sticks if `defaultRate` is kept in sync too — not just `rate` itself.
            player?.defaultRate = rate
            if isPlayingFlag { player?.rate = rate }
        }
    }

    public var volume: Float = 1.0 {
        didSet { player?.volume = volume }
    }

    public var currentTime: TimeInterval {
        player?.currentTime().seconds ?? 0
    }

    public private(set) var duration: TimeInterval?

    private var player: AVPlayer?
    /// The item `player` currently plays, kept to identity-check every callback (duration load,
    /// end-of-item, periodic time) against — closures below capture the `item`/`player` that were
    /// current when they were installed, so a stale callback from a since-replaced item (e.g. a
    /// fast `load(next)` right after this one) can't leak a reading into the new item's state.
    private var currentItem: AVPlayerItem?
    private var timeObserver: Any?
    private var endOfItemObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var isPlayingFlag = false
    private var durationLoadTask: Task<Void, Never>?
    /// Where to seek once the current item becomes ready; set by `load`, consumed and cleared once
    /// applied.
    private var pendingStartPosition: TimeInterval = 0
    /// Whether the current item has become ready (and, if it had a non-zero `pendingStartPosition`,
    /// had that seek applied). `onTimeUpdate` ticks are suppressed until this is true: a tick that
    /// arrives before the restore seek lands would otherwise report (and let `Playback` save) the
    /// pre-seek position, e.g. 0, overwriting the real saved position.
    private var isItemReady = false

    public init() {}

    isolated deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        statusObserver?.invalidate()
        durationLoadTask?.cancel()
    }

    public func load(url: URL, startPosition: TimeInterval) {
        tearDownCurrentItem()
        duration = nil
        isPlayingFlag = false
        pendingStartPosition = startPosition
        isItemReady = false

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        newPlayer.defaultRate = rate
        player = newPlayer
        currentItem = item

        durationLoadTask = Task { @MainActor [weak self] in
            guard let loadedDuration = try? await item.asset.load(.duration) else { return }
            let seconds = loadedDuration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            guard let self, !Task.isCancelled, self.currentItem === item else { return }
            self.duration = seconds
            self.onDurationAvailable?(seconds)
        }

        // Defer the restore seek (and reporting any time update) until the item reports ready,
        // the way the old service's `seekWhenReady` did: seeking an item that isn't ready yet
        // silently drops the seek instead of queuing it.
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard observedItem.status == .readyToPlay else { return }
            Task { @MainActor [weak self] in
                guard let self, self.currentItem === observedItem, !self.isItemReady else { return }
                if self.pendingStartPosition > 0 {
                    await observedItem.seek(to: CMTime(seconds: self.pendingStartPosition, preferredTimescale: 600))
                }
                self.isItemReady = true
                self.statusObserver = nil
                if self.isPlayingFlag {
                    self.player?.rate = self.rate
                    self.player?.play()
                }
            }
        }

        endOfItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentItem === item else { return }
                await self.onEndOfItem?()
            }
        }

        // Passing `queue: nil` delivers the block on the main queue.
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self, self.currentItem === item, self.isItemReady else { return }
                await self.onTimeUpdate?(seconds)
            }
        }
    }

    public func play() {
        isPlayingFlag = true
        // If the item isn't ready yet, the status-readiness callback above starts playback once it
        // is (applying the restore seek first); nothing to do here until then.
        guard isItemReady else { return }
        player?.rate = rate
        player?.play()
    }

    public func pause() {
        isPlayingFlag = false
        player?.pause()
    }

    public func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 1))
    }

    private func tearDownCurrentItem() {
        durationLoadTask?.cancel()
        durationLoadTask = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        endOfItemObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        currentItem = nil
        isItemReady = false
        player?.pause()
        player = nil
    }
}

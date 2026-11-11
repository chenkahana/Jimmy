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
    private var timeObserver: Any?
    private var endOfItemObserver: NSObjectProtocol?
    private var isPlayingFlag = false
    private var durationLoadTask: Task<Void, Never>?

    public init() {}

    isolated deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let endOfItemObserver {
            NotificationCenter.default.removeObserver(endOfItemObserver)
        }
        durationLoadTask?.cancel()
    }

    public func load(url: URL) {
        tearDownCurrentItem()
        duration = nil
        isPlayingFlag = false

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        player = newPlayer

        durationLoadTask = Task { @MainActor [weak self] in
            guard let loadedDuration = try? await item.asset.load(.duration) else { return }
            let seconds = loadedDuration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            guard let self, !Task.isCancelled else { return }
            self.duration = seconds
            self.onDurationAvailable?(seconds)
        }

        endOfItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.onEndOfItem?()
            }
        }

        // Passing `queue: nil` delivers the block on the main queue.
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                await self?.onTimeUpdate?(seconds)
            }
        }
    }

    public func play() {
        isPlayingFlag = true
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
        player?.pause()
        player = nil
    }
}

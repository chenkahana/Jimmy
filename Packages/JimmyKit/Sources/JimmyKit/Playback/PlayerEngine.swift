import Foundation

/// The minimal surface `Playback` needs from a media player. Lets tests substitute a fake
/// engine instead of driving real `AVPlayer`/`AVAudioSession` machinery.
public protocol PlayerEngine: AnyObject {
    /// Playback rate; 1.0 is normal speed. Setting it while playing should take effect immediately.
    var rate: Float { get set }

    /// Output volume, 0...1. Used for the sleep timer's fade-out; 1.0 is full volume.
    var volume: Float { get set }

    /// Current playback position, in seconds.
    var currentTime: TimeInterval { get }

    /// Duration of the loaded item, once known. `nil` before the item is ready.
    var duration: TimeInterval? { get }

    /// Called periodically (about once a second) while an item is loaded, with the current position.
    /// `async` so `Playback` can await its own save-to-store work instead of spawning a detached
    /// fire-and-forget task for it.
    var onTimeUpdate: ((TimeInterval) async -> Void)? { get set }

    /// Called once, when the duration of a newly-loaded item becomes known.
    var onDurationAvailable: ((TimeInterval) -> Void)? { get set }

    /// Called when playback reaches the end of the loaded item.
    var onEndOfItem: (() async -> Void)? { get set }

    /// Load a new item for playback, replacing whatever was loaded before. Does not start playing.
    func load(url: URL)

    /// Start/resume playback of the loaded item.
    func play()

    /// Pause playback.
    func pause()

    /// Move the playhead to `time`, in seconds.
    func seek(to time: TimeInterval)
}

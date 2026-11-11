#if canImport(MediaPlayer)
import Foundation
import MediaPlayer

/// Publishes now-playing metadata to `MPNowPlayingInfoCenter` for the lock screen, Control
/// Center, and CarPlay. Artwork is supplied by the caller (already-fetched `MPMediaItemArtwork`);
/// this controller does not fetch artwork itself — that's a network concern that belongs to the
/// app layer, not this package.
public final class NowPlayingController {
    public init() {}

    public func update(
        title: String,
        podcastTitle: String?,
        duration: TimeInterval?,
        elapsed: TimeInterval,
        rate: Float,
        artwork: MPMediaItemArtwork? = nil
    ) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = podcastTitle
        info[MPMediaItemPropertyAlbumTitle] = podcastTitle
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
#endif

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
        defaultRate: Float = 1,
        chapter: (title: String, index: Int, count: Int)? = nil,
        artwork: MPMediaItemArtwork? = nil
    ) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        // The chapter, when there is one, takes the line under the title; the show stays as the album.
        info[MPMediaItemPropertyArtist] = chapter.map(\.title) ?? podcastTitle
        info[MPMediaItemPropertyAlbumTitle] = podcastTitle
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate
        if let chapter {
            info[MPNowPlayingInfoPropertyChapterNumber] = chapter.index
            info[MPNowPlayingInfoPropertyChapterCount] = chapter.count
        }
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

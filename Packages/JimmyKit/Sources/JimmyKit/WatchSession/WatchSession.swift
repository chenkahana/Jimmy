import Foundation

/// The message format the phone and watch exchange over `WatchConnectivity`. Plain `Codable`
/// structs/enum, with no dependency on `WatchConnectivity` itself, so both targets — and these
/// tests — can use them without linking anything watch-session-specific.

/// Now-playing snapshot the phone pushes to the watch.
public nonisolated struct WatchNowPlaying: Sendable, Hashable, Codable {
    public var episodeID: UUID
    public var title: String
    public var showTitle: String?
    public var artworkURL: URL?
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var isPlaying: Bool
    public var rate: Float

    public init(
        episodeID: UUID,
        title: String,
        showTitle: String? = nil,
        artworkURL: URL? = nil,
        position: TimeInterval,
        duration: TimeInterval? = nil,
        isPlaying: Bool,
        rate: Float
    ) {
        self.episodeID = episodeID
        self.title = title
        self.showTitle = showTitle
        self.artworkURL = artworkURL
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.rate = rate
    }
}

/// One row in the watch's Queue or Recent list.
public nonisolated struct WatchEpisodeSummary: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var showTitle: String?

    public init(id: UUID, title: String, showTitle: String? = nil) {
        self.id = id
        self.title = title
        self.showTitle = showTitle
    }
}

/// Everything the watch shows, pushed from the phone via `WCSession.updateApplicationContext`
/// (and sent in reply to the watch's own request for the current state).
public nonisolated struct WatchSessionState: Sendable, Hashable, Codable {
    public static let maxQueueCount = 50
    public static let maxRecentCount = 20

    public var nowPlaying: WatchNowPlaying?
    public var queue: [WatchEpisodeSummary]
    public var recent: [WatchEpisodeSummary]

    public init(
        nowPlaying: WatchNowPlaying? = nil,
        queue: [WatchEpisodeSummary] = [],
        recent: [WatchEpisodeSummary] = []
    ) {
        self.nowPlaying = nowPlaying
        self.queue = Array(queue.prefix(Self.maxQueueCount))
        self.recent = Array(recent.prefix(Self.maxRecentCount))
    }
}

/// A control message the watch sends to the phone, applied through `AppModel` the same way a tap
/// in the phone's own UI would be.
public nonisolated enum WatchCommand: Sendable, Hashable, Codable {
    case play
    case pause
    case skipForward
    case skipBackward
    case playEpisode(UUID)
    case removeFromQueue(UUID)
}

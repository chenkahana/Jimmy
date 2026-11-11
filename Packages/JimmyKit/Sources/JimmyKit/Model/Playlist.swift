import Foundation

/// The dynamic rule a smart playlist filters episodes by; mirrors today's `SmartPlaylistType`.
public enum PlaylistRule: String, Sendable, Hashable, Codable, CaseIterable {
    case recentlyAdded
    case inProgress
    case downloaded
    case unplayed
    case starred
}

/// A smart playlist definition: a name paired with the rule that selects its episodes.
public nonisolated struct Playlist: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var rule: PlaylistRule

    public init(id: UUID = UUID(), name: String, rule: PlaylistRule) {
        self.id = id
        self.name = name
        self.rule = rule
    }
}

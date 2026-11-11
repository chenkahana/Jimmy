import Foundation
import JimmyKit

/// Predefined smart playlists that map to dynamic GRDB queries
enum SmartPlaylistType: String, CaseIterable, Identifiable, Codable {
    case recentlyAdded
    case inProgress
    case downloaded
    case unplayed
    case starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .inProgress: return "In Progress"
        case .downloaded: return "Downloaded"
        case .unplayed: return "Unplayed"
        case .starred: return "Starred"
        }
    }

    var icon: String {
        switch self {
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .inProgress: return "play.circle"
        case .downloaded: return "arrow.down.circle.fill"
        case .unplayed: return "circle"
        case .starred: return "star.fill"
        }
    }

    var color: String {
        switch self {
        case .recentlyAdded: return "blue"
        case .inProgress: return "orange"
        case .downloaded: return "green"
        case .unplayed: return "purple"
        case .starred: return "yellow"
        }
    }

    /// The `JimmyKit.PlaylistRule` this UI-only type presents — the two mirror each other case
    /// for case; `Store.episodes(matching:)`/`episodeCount(matching:)` take the `JimmyKit` one.
    var rule: PlaylistRule {
        switch self {
        case .recentlyAdded: return .recentlyAdded
        case .inProgress: return .inProgress
        case .downloaded: return .downloaded
        case .unplayed: return .unplayed
        case .starred: return .starred
        }
    }
}

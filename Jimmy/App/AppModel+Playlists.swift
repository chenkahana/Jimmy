import Foundation
import JimmyKit

/// Smart playlists: `Store`'s `playlists` table and the rule-filtered episode queries that back
/// it. Replaces `SmartPlaylistService`, which queried the legacy `episodes`/`playback_state`
/// columns directly instead of `progress`/`downloads`.
extension AppModel {
    func playlists() async -> [JimmyKit.Playlist] {
        (try? await readyStore?.playlists()) ?? []
    }

    func episodes(for rule: JimmyKit.PlaylistRule, limit: Int = 50) async -> [JimmyKit.EpisodeListItem] {
        (try? await readyStore?.episodes(matching: rule, limit: limit)) ?? []
    }

    func episodeCount(for rule: JimmyKit.PlaylistRule) async -> Int {
        (try? await readyStore?.episodeCount(matching: rule)) ?? 0
    }
}

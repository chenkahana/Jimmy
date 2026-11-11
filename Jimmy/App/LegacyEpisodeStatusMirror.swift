import Foundation

/// Mirrors a played/unplayed toggle into the legacy `episodes.status`/`.played` columns and
/// `playback_state.finished`, then posts `.episodeStatusUpdated` — replicating exactly what the
/// deleted `EpisodeService.setEpisodePlayed`/`.updateEpisodeStatus` did. Used by
/// `LegacyProgressMirror` (mirroring a `Playback` save) and by `AppModel.markPlayed`/
/// `.markUnplayed` (so `QueueView`, `SubscriptionViewModel`, and `ProgressCacheStore` — none of
/// which reads `JimmyKit`'s `progress` yet — stay in sync no matter which API flips the bit).
/// Delete this once those three move onto `JimmyKit` directly.
enum LegacyEpisodeStatusMirror {
    static func markPlayed(_ episode: Episode) {
        mirror(episode, isFinished: true)
    }

    static func markUnplayed(_ episode: Episode) {
        mirror(episode, isFinished: false)
    }

    private static func mirror(_ episode: Episode, isFinished: Bool) {
        guard episode.status.contains(.played) != isFinished else { return }

        Task.detached(priority: .utility) {
            var updated = episode
            if isFinished {
                updated.status.insert(.played)
            } else {
                updated.status.remove(.played)
            }
            updated.played = isFinished

            try? await DatabaseManager.shared.writeAsync { db in
                let exists = try Episode.fetchOne(db, key: updated.id) != nil
                if exists {
                    try db.execute(
                        sql: "UPDATE episodes SET status = ?, played = ? WHERE id = ?",
                        arguments: [updated.status.rawValue, updated.played, updated.id]
                    )
                } else if updated.podcastID != nil {
                    try updated.save(db)
                }
            }

            let playbackStateRepository = DIContainer.shared.playbackStateRepository
            let currentState = (try? await playbackStateRepository.fetchPlaybackState(for: updated.id))
                ?? PlaybackState(episodeID: updated.id, position: 0, finished: false)
            try? await playbackStateRepository.savePlaybackState(
                PlaybackState(episodeID: updated.id, position: currentState.position, finished: isFinished, updatedAt: Date())
            )

            await MainActor.run {
                NotificationCenter.default.post(name: .episodeStatusUpdated, object: updated)
            }
        }
    }
}

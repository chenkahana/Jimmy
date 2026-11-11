import Foundation
import JimmyKit

/// Wraps JimmyKit's `StorePlaybackSource` (the real progress store `Playback` reads from) and
/// additionally mirrors every save into the legacy columns (`episodes.playbackPosition`,
/// `episodes.played`/`.status`, `playback_state.position`/`.finished`).
///
/// PR 18 moved podcast detail, episode rows, and episode detail onto `progress` directly, and
/// PR 20 moved `AppDataDocument` (iCloud sync) and smart playlists off these columns too, but this
/// still can't be deleted: `QueueView`, `SharedDataStore` (widget payload),
/// `EpisodeIDMigrationService`, `CarPlayManager`, and `ProgressCacheStore`/`SubscriptionViewModel`
/// (via `.episodeStatusUpdated`) all still read these legacy columns. Delete this — and build
/// `Playback` with a bare `StorePlaybackSource` instead — once every one of those moves onto
/// `JimmyKit` too.
@MainActor
struct LegacyProgressMirror: ProgressStore {
    private let inner: StorePlaybackSource
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    /// Marks an episode played via `LegacyEpisodeStatusMirror` (status bit, legacy `played`
    /// column, `.episodeStatusUpdated` notification). Injectable so tests don't have to go
    /// through the real `DatabaseManager` singleton.
    private let markEpisodePlayed: (Episode) -> Void

    init(
        store: Store,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        markEpisodePlayed: @escaping (Episode) -> Void = { LegacyEpisodeStatusMirror.markPlayed($0) }
    ) {
        self.inner = StorePlaybackSource(store: store)
        self.playbackStateRepository = playbackStateRepository
        self.episodeRepository = episodeRepository
        self.markEpisodePlayed = markEpisodePlayed
    }

    func loadProgress(for episodeID: UUID) async -> JimmyKit.Progress? {
        await inner.loadProgress(for: episodeID)
    }

    func saveProgress(_ progress: JimmyKit.Progress) async {
        await inner.saveProgress(progress)
        await mirrorToLegacyColumns(progress)
    }

    /// Writes the same legacy columns `AudioPlayerService` used to: `playback_state.position`
    /// (which also updates `episodes.playbackPosition` — see
    /// `GRDBPlaybackStateRepository.savePlaybackState`) on every save, and — using the same
    /// `>= 0.95` finished rule `Progress.isFinished` already applies — `episodes.played`/`.status`
    /// once an episode crosses it, through `markEpisodePlayed` so the existing
    /// `.episodeStatusUpdated` notification still fires for any old screen listening for it.
    private func mirrorToLegacyColumns(_ progress: JimmyKit.Progress) async {
        let legacyState = PlaybackState(
            episodeID: progress.episodeID,
            position: progress.position,
            finished: progress.isFinished,
            updatedAt: progress.updatedAt
        )
        try? await playbackStateRepository.savePlaybackState(legacyState)

        guard progress.isFinished,
              let episodeWithState = try? await episodeRepository.fetchEpisode(by: progress.episodeID),
              !episodeWithState.episode.status.contains(.played) else { return }
        markEpisodePlayed(episodeWithState.episode)
    }
}

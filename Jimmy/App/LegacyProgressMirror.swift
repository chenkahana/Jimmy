import Foundation
import JimmyKit

/// Wraps JimmyKit's `StorePlaybackSource` (the real progress store `Playback` reads from) and
/// additionally mirrors every save into the legacy columns (`episodes.playbackPosition`,
/// `episodes.played`/`.status`, `playback_state.position`/`.finished`) that library, podcast
/// detail and episode rows (PRs 17-18) still read until they move onto `progress` directly.
///
/// Delete this type — and build `Playback` with a bare `StorePlaybackSource` instead — once PR 18
/// moves those screens onto `JimmyKit`.
@MainActor
struct LegacyProgressMirror: ProgressStore {
    private let inner: StorePlaybackSource
    private let playbackStateRepository: PlaybackStateRepositoryProtocol
    private let episodeRepository: EpisodeRepositoryProtocol
    /// Marks an episode played, the way `EpisodeService.setEpisodePlayed` does (status bit,
    /// legacy `played` column, `.episodeStatusUpdated` notification). Injectable so tests don't
    /// have to go through the real `EpisodeService`/`DatabaseManager` singletons.
    private let markEpisodePlayed: (Episode) -> Void

    init(
        store: Store,
        playbackStateRepository: PlaybackStateRepositoryProtocol = DIContainer.shared.playbackStateRepository,
        episodeRepository: EpisodeRepositoryProtocol = DIContainer.shared.episodeRepository,
        markEpisodePlayed: @escaping (Episode) -> Void = { EpisodeService.shared.setEpisodePlayed($0) }
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
    /// once an episode crosses it, through `EpisodeService.setEpisodePlayed` so the existing
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

import Foundation

/// One row of an episode list: the episode itself joined with everything a list or detail screen
/// needs to render it — progress, queue membership, and download state — so screens don't each
/// re-derive these from three separate reads. Returned by `Store.observeEpisodes(podcastID:)`.
public nonisolated struct EpisodeListItem: Sendable, Hashable, Identifiable {
    public var episode: Episode
    public var progress: Progress?
    public var isQueued: Bool
    public var downloadState: DownloadState?

    public var id: UUID { episode.id }

    public init(episode: Episode, progress: Progress? = nil, isQueued: Bool = false, downloadState: DownloadState? = nil) {
        self.episode = episode
        self.progress = progress
        self.isQueued = isQueued
        self.downloadState = downloadState
    }
}

import SwiftUI
import JimmyKit
import os

/// The episode list embedded in `PodcastDetailView`. Reads `podcastID`'s episodes — joined with
/// progress, queue membership, and download state — straight from `AppModel`'s `Store`, staying
/// current automatically as any of that changes (no notification plumbing needed).
struct PodcastEpisodeListView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastEpisodeListView")
    @Environment(AppModel.self) private var appModel
    let podcastID: UUID
    let podcastTitle: String
    let podcastArtworkURL: URL?
    let filterOption: PodcastDetailViewModel.EpisodeFilter
    let sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    let onEpisodeTap: (EpisodeWithPlaybackState) -> Void

    @State private var items: [EpisodeListItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                emptyView
            } else {
                episodesList
            }
        }
        .task(id: podcastID) {
            guard let stream = appModel.observeEpisodes(podcastID: podcastID) else { return }
            do {
                for try await newItems in stream {
                    items = newItems
                }
            } catch {
                logger.error("PodcastEpisodeListView: observeEpisodes stopped: \(error)")
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Episodes Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("This podcast may not have any episodes yet.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var episodesList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredAndSortedItems) { item in
                let legacyEpisode = item.asLegacyEpisode()
                let episodeWithStatus = episodeWithStatus(item, legacyEpisode: legacyEpisode)

                EpisodeCard(
                    episode: episodeWithStatus,
                    onTap: {
                        let episodeWithState = EpisodeWithPlaybackState(
                            episode: legacyEpisode,
                            playbackState: PlaybackState(
                                episodeID: item.episode.id,
                                position: item.progress?.position ?? 0,
                                finished: item.progress?.isFinished ?? false,
                                updatedAt: Date()
                            )
                        )
                        onEpisodeTap(episodeWithState)
                    },
                    onPlay: {
                        Task { await appModel.play(item.episode) }
                    },
                    onAddToQueue: {
                        Task { await appModel.enqueue(item.episode.id) }
                    },
                    onToggleFinished: {
                        Task {
                            if item.progress?.isFinished == true {
                                await appModel.markUnplayed(item.episode.id)
                            } else {
                                await appModel.markPlayed(item.episode.id)
                            }
                        }
                    }
                )
                .episodeContextMenu(
                    episode: legacyEpisode,
                    downloadState: appModel.downloadState(for: item.episode.id),
                    onAddToQueue: {
                        Task { await appModel.enqueue(item.episode.id) }
                    },
                    onMarkAsPlayed: {
                        Task {
                            if item.progress?.isFinished == true {
                                await appModel.markUnplayed(item.episode.id)
                            } else {
                                await appModel.markPlayed(item.episode.id)
                            }
                        }
                    },
                    onPlayNext: {
                        Task { await appModel.playNext(item.episode.id) }
                    },
                    onShare: {},
                    onDownload: { appModel.download(item.episode) },
                    onCancelDownload: { appModel.cancelDownload(item.episode.id) },
                    onDeleteDownload: { appModel.deleteDownload(item.episode.id) }
                )
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Data processing

    private var filteredAndSortedItems: [EpisodeListItem] {
        var filtered = items

        switch filterOption {
        case .all:
            break
        case .unplayed:
            filtered = filtered.filter { !($0.progress?.isFinished ?? false) }
        case .played:
            filtered = filtered.filter { $0.progress?.isFinished ?? false }
        case .downloaded:
            filtered = filtered.filter { appModel.isDownloaded($0.episode.id) }
        }

        switch sortOrder {
        case .newestFirst:
            filtered.sort { ($0.episode.publishedDate ?? .distantPast) > ($1.episode.publishedDate ?? .distantPast) }
        case .oldestFirst:
            filtered.sort { ($0.episode.publishedDate ?? .distantPast) < ($1.episode.publishedDate ?? .distantPast) }
        case .titleAZ:
            filtered.sort { $0.episode.title < $1.episode.title }
        case .titleZA:
            filtered.sort { $0.episode.title > $1.episode.title }
        }

        return filtered
    }

    private func episodeWithStatus(_ item: EpisodeListItem, legacyEpisode: Jimmy.Episode) -> EpisodeWithStatus {
        let isCurrentlyPlaying = (appModel.playback?.isPlaying ?? false) && appModel.playback?.currentEpisode?.id == item.episode.id
        let duration = item.progress?.duration ?? item.episode.duration
        let playProgress: Double
        if let duration, duration > 0 {
            playProgress = (item.progress?.position ?? 0) / duration
        } else {
            playProgress = 0
        }

        let status = EpisodeWithStatus.deriveStatus(
            episode: legacyEpisode,
            playProgress: playProgress,
            isQueued: item.isQueued,
            isCurrentlyPlaying: isCurrentlyPlaying
        )

        return EpisodeWithStatus(
            episode: legacyEpisode,
            podcastTitle: podcastTitle,
            playProgress: playProgress,
            status: status,
            podcastArtworkURL: podcastArtworkURL
        )
    }
}

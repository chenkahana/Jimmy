import SwiftUI
import JimmyKit

/// The episode rows of `PodcastDetailView`, inside its `List`. `items` is `podcastID`'s episodes, joined
/// with progress, queue membership and download state, as `AppModel`'s `Store` publishes them; `nil`
/// while the first batch loads.
struct PodcastEpisodeListView: View {
    @Environment(AppModel.self) private var appModel
    let items: [EpisodeListItem]?
    let podcastTitle: String
    let podcastArtworkURL: URL?
    let filterOption: PodcastDetailViewModel.EpisodeFilter
    let sortOrder: PodcastDetailViewModel.EpisodeSortOrder
    let onEpisodeTap: (EpisodeWithPlaybackState) -> Void

    var body: some View {
        if let items {
            let visible = filteredAndSorted(items)
            if visible.isEmpty {
                ContentUnavailableView(
                    items.isEmpty ? "No Episodes" : "No \(filterOption.rawValue) Episodes",
                    systemImage: "list.bullet",
                    description: items.isEmpty ? Text("Episodes appear here when the show publishes them.") : nil
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(visible) { item in
                    row(item)
                }
            }
        } else {
            EpisodePlaceholderRows()
        }
    }

    private func row(_ item: EpisodeListItem) -> some View {
        let legacyEpisode = item.asLegacyEpisode()
        let isFinished = item.progress?.isFinished ?? false
        let downloadState = appModel.downloadState(for: item.episode.id)
        let toggleFinished = {
            Task {
                if isFinished {
                    await appModel.markUnplayed(item.episode.id)
                } else {
                    await appModel.markPlayed(item.episode.id)
                }
            }
        }

        return EpisodeCard(
            episode: episodeWithStatus(item, legacyEpisode: legacyEpisode),
            onTap: {
                onEpisodeTap(EpisodeWithPlaybackState(
                    episode: legacyEpisode,
                    playbackState: PlaybackState(
                        episodeID: item.episode.id,
                        position: item.progress?.position ?? 0,
                        finished: isFinished,
                        updatedAt: Date()
                    )
                ))
            },
            showsArtwork: false
        )
        .swipeActions(edge: .leading) {
            queueButtons(item.episode)
        }
        .swipeActions(edge: .trailing) {
            Button(isFinished ? "Unplayed" : "Played", systemImage: isFinished ? "circle" : "checkmark.circle") {
                toggleFinished()
            }
            downloadButton(item.episode, state: downloadState)
        }
        .contextMenu {
            Button("Play", systemImage: "play") {
                Task { await appModel.play(item.episode) }
            }
            queueButtons(item.episode)
            Button(isFinished ? "Mark as Unplayed" : "Mark as Played",
                   systemImage: isFinished ? "circle" : "checkmark.circle") {
                toggleFinished()
            }
            downloadButton(item.episode, state: downloadState)
            if let audioURL = legacyEpisode.audioURL {
                ShareLink(item: audioURL)
            }
        }
    }

    @ViewBuilder
    private func queueButtons(_ episode: JimmyKit.Episode) -> some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Task { await appModel.playNext(episode.id) }
        }
        Button("Add to Queue", systemImage: "text.append") {
            Task { await appModel.enqueue(episode.id) }
        }
    }

    @ViewBuilder
    private func downloadButton(_ episode: JimmyKit.Episode, state: JimmyKit.DownloadState?) -> some View {
        switch state {
        case nil, .failed:
            Button("Download", systemImage: "arrow.down.circle") { appModel.download(episode) }
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") { appModel.cancelDownload(episode.id) }
        case .done:
            Button("Remove Download", systemImage: "trash", role: .destructive) { appModel.deleteDownload(episode.id) }
        }
    }

    // MARK: - Data processing

    private func filteredAndSorted(_ items: [EpisodeListItem]) -> [EpisodeListItem] {
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
        let isCurrentlyPlaying = (appModel.playback?.isPlaying ?? false)
            && appModel.playback?.currentEpisode?.id == item.episode.id
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

/// Rows shaped like episodes, redacted, while a show's episodes load.
struct EpisodePlaceholderRows: View {
    var body: some View {
        ForEach(0..<5, id: \.self) { _ in
            EpisodeCard(
                episode: EpisodeWithStatus(
                    episode: Jimmy.Episode(
                        id: UUID(),
                        title: "An episode title that runs to two lines",
                        publishedDate: Date(),
                        duration: 2700,
                        artworkURL: nil,
                        description: nil
                    ),
                    podcastTitle: ""
                ),
                onTap: {},
                showsArtwork: false
            )
            .redacted(reason: .placeholder)
            .disabled(true)
        }
    }
}

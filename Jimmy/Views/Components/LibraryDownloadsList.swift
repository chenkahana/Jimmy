import JimmyKit
import SwiftUI

/// Library's Downloads segment: what's downloading (with progress), what failed, what's on this iPhone, and how much
/// space it takes. Files stay on the device; nothing here talks to a server except a retried download.
struct LibraryDownloadsList: View {
    let items: [JimmyKit.EpisodeListItem]
    let podcasts: [JimmyKit.Podcast]
    let onOpen: (JimmyKit.EpisodeListItem) -> Void

    @Environment(AppModel.self) private var appModel
    @State private var bytesOnDevice: Int64?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
            section("Downloading", inProgress)
            section("Couldn't Download", failed)
            section("On This iPhone", done)
            if let bytesOnDevice, !done.isEmpty {
                Text("^[\(done.count) episode](inflect: true) · \(bytesOnDevice.formatted(.byteCount(style: .file))) on this iPhone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .task(id: done.map(\.id)) { await measure() }
    }

    // MARK: - Groups

    private func state(_ item: JimmyKit.EpisodeListItem) -> JimmyKit.DownloadState? {
        appModel.downloadState(for: item.id)
    }

    private var inProgress: [JimmyKit.EpisodeListItem] {
        items.filter { [.queued, .downloading].contains(state($0)) }
    }

    private var failed: [JimmyKit.EpisodeListItem] {
        items.filter { state($0) == .failed }
    }

    private var done: [JimmyKit.EpisodeListItem] {
        items.filter { state($0) == .done }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [JimmyKit.EpisodeListItem]) -> some View {
        if !rows.isEmpty {
            Text(title)
                .font(.headline)
                .padding(.top, JimmyDesign.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { item in
                let state = state(item)
                DownloadRow(
                    item: item,
                    podcast: podcast(of: item),
                    state: state,
                    progress: appModel.downloads?.progress[item.id] ?? 0,
                    onOpen: onOpen
                )
                // A new row when the state changes, so its swipe actions never outlive the state they were made for.
                .id("\(item.id)-\(String(describing: state))")
            }
        }
    }

    private func podcast(of item: JimmyKit.EpisodeListItem) -> JimmyKit.Podcast? {
        podcasts.first { $0.id == item.episode.podcastID }
    }

    /// Sums the finished files' sizes off the main actor.
    private func measure() async {
        let urls = done.compactMap { appModel.downloads?.fileURL(for: $0.id) }
        bytesOnDevice = await Task.detached(priority: .utility) {
            urls.reduce(Int64(0)) { total, url in
                let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
                return total + Int64(size)
            }
        }.value
    }
}

private struct DownloadRow: View {
    let item: JimmyKit.EpisodeListItem
    let podcast: JimmyKit.Podcast?
    let state: JimmyKit.DownloadState?
    let progress: Double
    let onOpen: (JimmyKit.EpisodeListItem) -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button { onOpen(item) } label: {
            HStack(alignment: .top, spacing: JimmyDesign.Spacing.md) {
                EpisodeArtwork(
                    episodeArtworkURL: item.episode.artworkURL,
                    podcastArtworkURL: podcast?.artworkURL,
                    size: 56
                )
                VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
                    Text(item.episode.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if state == .queued || state == .downloading {
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the episode")
        .swipeActions(edge: .trailing) { actions }
        .contextMenu {
            Button("Play", systemImage: "play") {
                Task { await appModel.play(item.episode) }
            }
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) {
                appModel.cancelDownload(item.id)
            }
        case .failed:
            Button("Try Again", systemImage: "arrow.clockwise") { appModel.download(item.episode) }
                .tint(JimmyDesign.SwipeTint.download)
            Button("Remove", systemImage: "trash", role: .destructive) { appModel.deleteDownload(item.id) }
        case .done:
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                appModel.deleteDownload(item.id)
            }
        case nil:
            EmptyView()
        }
    }

    /// "Show · 42 min" plus the download's own state while it isn't finished.
    private var details: String {
        var parts: [String] = []
        if let title = podcast?.title, !title.isEmpty { parts.append(title) }
        switch state {
        case .queued: parts.append("Waiting")
        case .downloading:
            parts.append(progress.formatted(.percent.precision(.fractionLength(0))))
        default:
            if let duration = item.progress?.duration ?? item.episode.duration, duration > 0 {
                parts.append(QueueTimeFormat.duration(duration))
            }
        }
        return parts.joined(separator: " · ")
    }
}

import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var downloadedEpisodes: [Episode] = []

    var body: some View {
        NavigationStack {
            Group {
                if downloadedEpisodes.isEmpty && activeDownloads.isEmpty {
                    emptyState
                } else {
                    downloadList
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !downloadedEpisodes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(formattedStorage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            refreshDownloadedEpisodes()
        }
        .onChange(of: downloadManager.downloadStates) { _ in
            refreshDownloadedEpisodes()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Downloads")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Episodes you download will appear here for offline listening.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var downloadList: some View {
        List {
            // Active downloads section
            if !activeDownloads.isEmpty {
                Section("Downloading") {
                    ForEach(activeDownloads, id: \.id) { episode in
                        ActiveDownloadRow(episode: episode, downloadManager: downloadManager)
                    }
                }
            }

            // Downloaded episodes section
            if !downloadedEpisodes.isEmpty {
                Section("Downloaded · \(formattedStorage)") {
                    ForEach(downloadedEpisodes) { episode in
                        DownloadedEpisodeRow(episode: episode, downloadManager: downloadManager)
                    }
                    .onDelete { indexSet in
                        deleteEpisodes(at: indexSet)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Computed

    private var activeDownloads: [Episode] {
        downloadManager.downloadStates.compactMap { id, state in
            guard state.isActive else { return nil }
            // We only have the ID here; reconstruct a minimal episode for display
            return downloadedEpisodes.first { $0.id == id }
        }
    }

    private var formattedStorage: String {
        let bytes = downloadManager.totalStorageUsed
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Actions

    private func refreshDownloadedEpisodes() {
        // Pull episodes that have a downloaded state
        let downloaded = downloadManager.downloadStates.filter { $0.value.isDownloaded }.keys
        // We only track UUIDs; update list based on known state
        downloadedEpisodes = downloadedEpisodes.filter { downloaded.contains($0.id) }
    }

    private func deleteEpisodes(at offsets: IndexSet) {
        for index in offsets {
            let episode = downloadedEpisodes[index]
            downloadManager.deleteDownload(for: episode)
        }
        downloadedEpisodes.remove(atOffsets: offsets)
    }
}

// MARK: - Active Download Row

private struct ActiveDownloadRow: View {
    let episode: Episode
    let downloadManager: DownloadManager

    private var state: DownloadState {
        downloadManager.downloadState(for: episode)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                switch state {
                case .queued:
                    Text("Queued")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .downloading(let progress):
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                default:
                    EmptyView()
                }
            }

            Spacer()

            Button {
                downloadManager.cancelDownload(for: episode)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Downloaded Episode Row

private struct DownloadedEpisodeRow: View {
    let episode: Episode
    let downloadManager: DownloadManager

    var body: some View {
        HStack(spacing: 12) {
            EpisodeArtworkView(
                episodeArtworkURL: episode.artworkURL,
                podcastArtworkURL: nil,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Downloaded")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let duration = episode.duration, duration > 0 {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDuration(Int(duration)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                downloadManager.deleteDownload(for: episode)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

#Preview {
    DownloadsView()
}

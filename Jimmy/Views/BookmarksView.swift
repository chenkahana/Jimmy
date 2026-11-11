import SwiftUI

/// Global bookmarks view showing all bookmarks grouped by episode
struct BookmarksView: View {
    @StateObject private var viewModel = BookmarkViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.bookmarks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No Bookmarks")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Tap the bookmark button while listening to save moments")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedBookmarks, id: \.key) { episodeID, bookmarks in
                        Section(header: Text(bookmarks.first.map { _ in "Episode" } ?? "")) {
                            ForEach(bookmarks) { bookmark in
                                BookmarkRow(bookmark: bookmark, onSeek: { timestamp in
                                    seekToBookmark(episodeID: episodeID, timestamp: timestamp)
                                }, onDelete: {
                                    Task { await viewModel.deleteBookmark(bookmark) }
                                })
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupedBookmarks: [(key: UUID, value: [Bookmark])] {
        let grouped = Dictionary(grouping: viewModel.bookmarks, by: { $0.episodeID })
        return grouped.sorted { $0.value.first?.createdAt ?? .distantPast > $1.value.first?.createdAt ?? .distantPast }
    }

    private func seekToBookmark(episodeID: UUID, timestamp: TimeInterval) {
        Task {
            // Load the episode and seek to the timestamp
            let episode = try? await DatabaseManager.shared.readAsync { db in
                try Episode.fetchOne(db, key: episodeID.uuidString)
            }
            if let episode = episode {
                await AudioPlayerService.shared.loadEpisode(episode, startPlaying: true)
                AudioPlayerService.shared.seek(to: timestamp)
            }
        }
    }
}

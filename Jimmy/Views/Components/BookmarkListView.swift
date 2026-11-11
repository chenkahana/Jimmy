import SwiftUI
import JimmyKit

/// Tappable list of bookmarks for a single episode. Tap seeks to timestamp. `viewModel` is owned
/// by the caller (e.g. `EpisodeDetailView`), which also needs it to add a bookmark at the current
/// playback position.
struct BookmarkListView: View {
    @ObservedObject var viewModel: BookmarkViewModel
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Group {
            if viewModel.bookmarks.isEmpty {
                Text("No bookmarks yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.bookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark, onSeek: onSeek) {
                            Task { await viewModel.deleteBookmark(bookmark) }
                        }
                    }
                }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    let onSeek: (TimeInterval) -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: { onSeek(bookmark.timestamp) }) {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimestamp(bookmark.timestamp))
                        .font(.system(.subheadline, design: .monospaced, weight: .medium))
                        .foregroundColor(.primary)

                    if !bookmark.note.isEmpty {
                        Text(bookmark.note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(bookmark.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

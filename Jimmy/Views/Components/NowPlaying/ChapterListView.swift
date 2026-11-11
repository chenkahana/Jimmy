import SwiftUI
import JimmyKit

/// Scrollable chapter list with current chapter highlighted. Tap to seek.
struct ChapterListView: View {
    @ObservedObject var viewModel: ChapterViewModel
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        if viewModel.chapters.isEmpty {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Text("No chapters available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        } else {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.chapters) { chapter in
                        ChapterRow(
                            chapter: chapter,
                            isCurrent: viewModel.currentChapter?.start == chapter.start,
                            onTap: { onSeek(chapter.start) }
                        )
                        .id(chapter.start)
                    }
                }
                .onChange(of: viewModel.currentChapter?.start) { newStart in
                    if let start = newStart {
                        withAnimation {
                            proxy.scrollTo(start, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

struct ChapterRow: View {
    let chapter: Chapter
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Chapter number indicator
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.system(.subheadline, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .accentColor : .primary)
                        .lineLimit(2)

                    Text(formatTimestamp(chapter.start))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

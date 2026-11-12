import SwiftUI
import JimmyKit

/// Chapter list with the current chapter marked. Tap to seek.
struct ChapterListView: View {
    @ObservedObject var viewModel: ChapterViewModel
    let onSeek: (TimeInterval) -> Void
    /// The episode's length, so the last chapter can show its length too.
    var duration: TimeInterval?

    var body: some View {
        if viewModel.chapters.isEmpty {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Text("This episode has no chapters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        } else {
            ScrollViewReader { proxy in
                LazyVStack(spacing: JimmyDesign.Spacing.xs) {
                    ForEach(Array(viewModel.chapters.enumerated()), id: \.element.id) { index, chapter in
                        let end = index + 1 < viewModel.chapters.count ? viewModel.chapters[index + 1].start : duration
                        ChapterRow(
                            chapter: chapter,
                            length: end.map { $0 - chapter.start },
                            isCurrent: viewModel.currentChapter?.start == chapter.start,
                            onTap: { onSeek(chapter.start) }
                        )
                        .id(chapter.start)
                    }
                }
                .onChange(of: viewModel.currentChapter?.start) { _, newStart in
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
    let length: TimeInterval?
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(2)

                Text(detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JimmyDesign.Spacing.md)
            .padding(.vertical, JimmyDesign.Spacing.sm)
            .background(isCurrent ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: JimmyDesign.Radius.md, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// "12:04 · 4 min"
    private var detail: String {
        let start = formatTimestamp(chapter.start)
        guard let length, length > 0 else { return start }
        return "\(start) · \(max(1, Int((length / 60).rounded()))) min"
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Chapters for the playing episode, with each chapter's length.
struct NowPlayingChaptersPanel: View {
    @StateObject private var chapters: ChapterViewModel
    let duration: TimeInterval?
    let onSeek: (TimeInterval) -> Void

    init(episodeID: UUID, duration: TimeInterval?, onSeek: @escaping (TimeInterval) -> Void) {
        _chapters = StateObject(wrappedValue: ChapterViewModel(episodeID: episodeID))
        self.duration = duration
        self.onSeek = onSeek
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
            Text("Chapters")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding([.horizontal, .top], JimmyDesign.Spacing.xl)

            if chapters.chapters.isEmpty {
                list
            } else {
                ScrollView { list }
            }
        }
        .padding(.bottom, JimmyDesign.Spacing.md)
    }

    private var list: some View {
        ChapterListView(viewModel: chapters, onSeek: onSeek, duration: duration)
            .padding(.horizontal, JimmyDesign.Spacing.md)
    }
}

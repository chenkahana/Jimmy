import SwiftUI
import JimmyKit

struct EpisodeDetailView: View {
    let episodeWithState: EpisodeWithPlaybackState
    @StateObject private var viewModel: EpisodeDetailViewModel
    @StateObject private var chapterViewModel: ChapterViewModel
    @StateObject private var transcriptViewModel: TranscriptViewModel
    @StateObject private var bookmarkViewModel: BookmarkViewModel
    @Environment(AppModel.self) private var appModel
    @State private var isTitleVisible = true
    @State private var showingCopiedMessage = false

    /// Show notes with tappable links and timestamps; `nil` when the feed has none.
    private let showNotes: AttributedString?
    private let readableWidth: CGFloat = 640
    static let seekScheme = "jimmy-seek"

    init(episodeWithState: EpisodeWithPlaybackState) {
        self.episodeWithState = episodeWithState
        self.showNotes = Self.showNotes(from: episodeWithState.episode.description)
        _viewModel = StateObject(wrappedValue: EpisodeDetailViewModel(
            episode: episodeWithState.episode
        ))
        _chapterViewModel = StateObject(wrappedValue: ChapterViewModel(episodeID: episodeWithState.episode.id))
        _transcriptViewModel = StateObject(wrappedValue: TranscriptViewModel(episodeID: episodeWithState.episode.id))
        _bookmarkViewModel = StateObject(wrappedValue: BookmarkViewModel(episodeID: episodeWithState.episode.id))
    }

    private var episode: Episode { episodeWithState.episode }
    private var title: String { episode.title.cleanedTitle }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xl) {
                header
                actions
                showNotesSection
                episodeDetailsSection
            }
            .frame(maxWidth: readableWidth, alignment: .leading)
            .padding(.horizontal, JimmyDesign.Spacing.lg)
            .padding(.vertical, JimmyDesign.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(isTitleVisible ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy Apple Podcasts Link", systemImage: "square.and.arrow.up", action: copyApplePodcastsURL)
            }
        }
        .alert("Link Copied", isPresented: $showingCopiedMessage) {
            Button("OK") { }
        } message: {
            Text("Apple Podcasts link has been copied to your clipboard.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.md) {
            BulletproofAsyncImage(url: episode.artworkURL ?? viewModel.podcast?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                JimmyDesign.Palette.fieldFill
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 120 * 0.18, style: .continuous))
            .shadow(
                color: JimmyDesign.Shadow.artworkColor,
                radius: JimmyDesign.Shadow.artworkRadius,
                y: JimmyDesign.Shadow.artworkY
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
                if let podcast = viewModel.podcast {
                    Text(podcast.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .onScrollVisibilityChange { isTitleVisible = $0 }
                if !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let duration = episode.duration, duration > 0,
               episodeWithState.playbackState.position > 0, !episodeWithState.playbackState.finished {
                ProgressView(value: min(episodeWithState.playbackState.position, duration), total: duration)
                    .tint(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
    }

    /// "Nov 3, 2026 · 38 min left".
    private var details: String {
        var parts: [String] = []
        if let date = episode.publishedDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        let position = episodeWithState.playbackState.position
        if episodeWithState.playbackState.finished {
            parts.append("Played")
        } else if let duration = episode.duration, duration > 0 {
            parts.append(position > 0
                ? "\(EpisodeCard.durationText(max(duration - position, 0))) left"
                : EpisodeCard.durationText(duration))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: JimmyDesign.Spacing.md) {
            Button(action: playEpisode) {
                Label(viewModel.isPlaying ? "Pause" : "Play",
                      systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)

            Button(viewModel.isInQueue ? "Remove from Queue" : "Add to Queue",
                   systemImage: viewModel.isInQueue ? "text.badge.minus" : "text.badge.plus",
                   action: toggleQueueStatus)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)

            Button(downloadButtonAccessibilityLabel, systemImage: downloadButtonIcon, action: downloadButtonTapped)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
        .controlSize(.large)
    }

    // MARK: - Show notes

    @ViewBuilder
    private var showNotesSection: some View {
        if let showNotes {
            Text(showNotes)
                .font(.body)
                .fontDesign(.serif)
                .lineSpacing(6)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == Self.seekScheme,
                          let seconds = TimeInterval(url.absoluteString.dropFirst(Self.seekScheme.count + 1))
                    else { return .systemAction }
                    seek(to: seconds)
                    return .handled
                })
        }
    }

    // MARK: - Chapters, Transcript, Bookmarks

    private var episodeDetailsSection: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xl) {
            detailSubsection(title: "Chapters") {
                ChapterListView(viewModel: chapterViewModel, onSeek: seek)
            }
            detailSubsection(title: "Transcript") {
                TranscriptView(viewModel: transcriptViewModel, onSeek: seek)
            }
            detailSubsection(title: "Bookmarks", trailing: addBookmarkButton) {
                BookmarkListView(viewModel: bookmarkViewModel, onSeek: seek)
            }
        }
    }

    private func detailSubsection<Content: View>(
        title: String, trailing: (some View)? = EmptyView(), @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            content()
        }
    }

    private var addBookmarkButton: some View {
        Button("Add Bookmark", systemImage: "bookmark") {
            Task {
                guard appModel.playback?.currentEpisode?.id == episode.id else { return }
                await bookmarkViewModel.addBookmark(timestamp: appModel.playback?.position ?? 0)
            }
        }
        .labelStyle(.iconOnly)
        .tint(.primary)
        .disabled(appModel.playback?.currentEpisode?.id != episode.id)
    }

    /// Seeks to `timestamp`, loading this episode first if it isn't already the one playing.
    private func seek(to timestamp: TimeInterval) {
        Task {
            if appModel.playback?.currentEpisode?.id != episode.id {
                await appModel.play(episode.asPlaybackEpisode())
            }
            await appModel.playback?.seek(to: timestamp)
        }
    }

    // MARK: - Actions

    private func playEpisode() {
        Task {
            if appModel.playback?.currentEpisode?.id == episode.id {
                // Same episode: toggle play/pause.
                await appModel.playback?.togglePlayPause()
            } else {
                // Different episode: load and play it.
                await appModel.play(episode.asPlaybackEpisode())
            }
        }
    }

    private func toggleQueueStatus() {
        Task {
            if viewModel.isInQueue {
                await AppModel.current?.dequeue(episode.id)
            } else {
                await AppModel.current?.enqueue(episode.id)
            }
        }
    }

    private func downloadButtonTapped() {
        switch viewModel.downloadState {
        case .queued, .downloading:
            viewModel.cancelDownload()
        case .done:
            viewModel.deleteDownload()
        case .failed, nil:
            viewModel.downloadEpisode()
        }
    }

    private var downloadButtonIcon: String {
        switch viewModel.downloadState {
        case .queued, .downloading: return "stop.circle"
        case .done: return "checkmark.circle"
        case .failed, nil: return "arrow.down.circle"
        }
    }

    private var downloadButtonAccessibilityLabel: String {
        switch viewModel.downloadState {
        case .queued, .downloading: return "Cancel Download"
        case .done: return "Remove Download"
        case .failed, nil: return "Download"
        }
    }

    private func copyApplePodcastsURL() {
        // A search URL for the show and episode titles: the feed carries no Apple Podcasts ID.
        let episodeTitle = episode.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let podcast = viewModel.podcast {
            let podcastTitle = podcast.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            UIPasteboard.general.string = "https://podcasts.apple.com/search?term=\(podcastTitle)+\(episodeTitle)"
        } else {
            UIPasteboard.general.string = "https://podcasts.apple.com/search?term=\(episodeTitle)"
        }
        showingCopiedMessage = true
    }
}

extension EpisodeDetailView {
    /// The description as text that keeps its paragraphs, list items and links, with bare web links
    /// and "12:34" / "1:02:03" timestamps as links too. A timestamp link seeks this episode.
    static func showNotes(from description: String?) -> AttributedString? {
        guard let description, !description.isEmpty else { return nil }

        // Block tags become line breaks; each <a> becomes its text between two private-use markers,
        // so its target can be put back after the rest of the HTML is stripped.
        var links: [URL?] = []
        let html = description
            .replacing(#/(?i)<br\s*/?>/#, with: "\n")
            .replacing(#/(?i)</(p|div|h[1-6]|ul|ol|blockquote)>/#, with: "\n\n")
            .replacing(#/(?i)<li[^>]*>/#, with: "\n• ")
            .replacing(#/(?is)<a\s[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>(.*?)</a>/#) { match in
                links.append(URL(string: String(match.1).cleanedDescription))
                return "\u{E000}\(match.2)\u{E001}"
            }
        let text = html
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).cleanedDescription }
            .joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var notes = AttributedString()
        for (index, chunk) in text.split(separator: "\u{E000}", omittingEmptySubsequences: false).enumerated() {
            guard index > 0 else {
                notes += AttributedString(String(chunk))
                continue
            }
            let parts = chunk.split(separator: "\u{E001}", maxSplits: 1, omittingEmptySubsequences: false)
            var link = AttributedString(String(parts[0]))
            if links.indices.contains(index - 1), let url = links[index - 1],
               ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
                link.link = url
            }
            notes += link
            if parts.count > 1 { notes += AttributedString(String(parts[1])) }
        }

        let plain = String(notes.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let url = match.url,
                      let range = Range(match.range, in: plain),
                      let linkRange = Range(range, in: notes),
                      notes[linkRange].link == nil else { continue }
                notes[linkRange].link = url
            }
        }

        for match in plain.matches(of: #/\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b/#) {
            let hours = match.1.flatMap { Int($0) } ?? 0
            guard let minutes = Int(match.2), let seconds = Int(match.3), minutes < 60, seconds < 60,
                  let linkRange = Range(match.range, in: notes),
                  let url = URL(string: "\(seekScheme):\(hours * 3600 + minutes * 60 + seconds)") else { continue }
            notes[linkRange].link = url
        }
        return notes
    }
}

#Preview {
    let sampleEpisode = Episode(
        id: UUID(),
        title: "Sample Episode",
        podcastID: UUID(),
        publishedDate: Date(),
        duration: 3600,
        artworkURL: nil,
        description: "This is a sample episode description. At 12:30 we talk about https://example.com.",
        audioURL: URL(filePath: "/episode.mp3")
    )

    NavigationStack {
        EpisodeDetailView(episodeWithState: EpisodeWithPlaybackState(
            episode: sampleEpisode,
            playbackState: PlaybackState(episodeID: sampleEpisode.id, position: 1245, finished: false)
        ))
    }
}

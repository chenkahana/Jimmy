import SwiftUI

/// An episode as a plain list row: title, then date and length, an accent dot while unplayed and a
/// thin accent progress line once started. Actions passed in appear in its context menu and, inside a
/// `List`, as swipe actions; a caller passing none can attach its own.
struct EpisodeCard: View, Equatable {
    let episode: EpisodeWithStatus
    let onTap: () -> Void
    let onPlay: (() -> Void)?
    let onAddToQueue: (() -> Void)?
    let onToggleFinished: (() -> Void)?

    // Queue-specific actions
    let onRemoveFromQueue: (() -> Void)?
    let onMoveToLast: (() -> Void)?
    let queuePosition: Int?
    /// Artwork and show title, for lists that mix shows.
    let showsArtwork: Bool

    init(
        episode: EpisodeWithStatus,
        onTap: @escaping () -> Void,
        onPlay: (() -> Void)? = nil,
        onAddToQueue: (() -> Void)? = nil,
        onToggleFinished: (() -> Void)? = nil,
        onRemoveFromQueue: (() -> Void)? = nil,
        onMoveToLast: (() -> Void)? = nil,
        queuePosition: Int? = nil,
        showsArtwork: Bool = true
    ) {
        self.episode = episode
        self.onTap = onTap
        self.onPlay = onPlay
        self.onAddToQueue = onAddToQueue
        self.onToggleFinished = onToggleFinished
        self.onRemoveFromQueue = onRemoveFromQueue
        self.onMoveToLast = onMoveToLast
        self.queuePosition = queuePosition
        self.showsArtwork = showsArtwork
    }

    private var isPlayed: Bool { episode.status == .played }
    private var isStarted: Bool { !isPlayed && episode.playProgress > 0 }
    private var isUnplayed: Bool { !isPlayed && episode.playProgress == 0 && episode.status != .playing }
    private var hasActions: Bool {
        onPlay != nil || onAddToQueue != nil || onToggleFinished != nil
            || onRemoveFromQueue != nil || onMoveToLast != nil
    }

    var body: some View {
        if hasActions {
            row
                .contextMenu { actionButtons }
                .swipeActions(edge: .leading) {
                    if let onAddToQueue {
                        Button("Add to Queue", systemImage: "text.append", action: onAddToQueue)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if let onRemoveFromQueue {
                        Button("Remove", systemImage: "trash", role: .destructive, action: onRemoveFromQueue)
                    }
                    if let onToggleFinished {
                        Button(isPlayed ? "Unplayed" : "Played", systemImage: isPlayed ? "circle" : "checkmark.circle",
                               action: onToggleFinished)
                    }
                }
        } else {
            row
        }
    }

    private var row: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: JimmyDesign.Spacing.md) {
                if showsArtwork {
                    EpisodeArtwork(
                        episodeArtworkURL: episode.artworkURL,
                        podcastArtworkURL: episode.podcastArtworkURL,
                        size: 56
                    )
                }

                VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
                    Text(episode.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isPlayed ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        if episode.status == .playing {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative)
                                .accessibilityLabel("Playing")
                        } else if isUnplayed {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("Unplayed")
                        }
                        Text(details)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if isStarted {
                        ProgressView(value: min(episode.playProgress, 1))
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
    }

    /// "Show · Nov 3 · 38 min left": the show only where shows mix.
    private var details: String {
        var parts: [String] = []
        if showsArtwork, !episode.podcastTitle.isEmpty { parts.append(episode.podcastTitle) }
        if let date = episode.publishedDate { parts.append(Self.dateText(date)) }
        if isPlayed {
            parts.append("Played")
        } else if episode.duration > 0 {
            let remaining = episode.duration * (1 - min(episode.playProgress, 1))
            parts.append(isStarted ? "\(Self.durationText(remaining)) left" : Self.durationText(episode.duration))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let onPlay {
            Button("Play", systemImage: "play", action: onPlay)
        }
        if let onAddToQueue {
            Button("Add to Queue", systemImage: "text.append", action: onAddToQueue)
        }
        if let onMoveToLast {
            Button("Move to End", systemImage: "arrow.down.to.line", action: onMoveToLast)
        }
        if let onToggleFinished {
            Button(isPlayed ? "Mark as Unplayed" : "Mark as Played",
                   systemImage: isPlayed ? "circle" : "checkmark.circle", action: onToggleFinished)
        }
        if let onRemoveFromQueue {
            Button("Remove from Queue", systemImage: "trash", role: .destructive, action: onRemoveFromQueue)
        }
    }

    static func dateText(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "42 min", "1 h 5 min".
    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    // MARK: - Equatable
    static func == (lhs: EpisodeCard, rhs: EpisodeCard) -> Bool {
        lhs.episode.id == rhs.episode.id &&
        lhs.episode.status == rhs.episode.status &&
        lhs.episode.playProgress == rhs.episode.playProgress
    }
}

// MARK: - Episode Artwork Component
struct EpisodeArtwork: View {
    let episodeArtworkURL: URL?
    let podcastArtworkURL: URL?
    let size: CGFloat

    var body: some View {
        BulletproofAsyncImage(url: episodeArtworkURL ?? podcastArtworkURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            JimmyDesign.Palette.fieldFill
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Episode Badges Component
struct EpisodeBadges: View {
    let status: EpisodeCardStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .playing:
                PlayingBadge()
            case .queued:
                QueuedBadge()
            case .played:
                PlayedBadge()
            case .none:
                EmptyView()
            }
        }
    }
}

struct PlayingBadge: View {
    var body: some View {
        AnimatedWaveformBars(barCount: 3, color: .accentColor, size: 12)
    }
}

struct QueuedBadge: View {
    var body: some View {
        Image(systemName: "list.bullet")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct PlayedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Preview
#Preview {
    List {
        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Sample Episode Title That Might Be Long",
                    publishedDate: Date(),
                    duration: 3600,
                    artworkURL: nil,
                    description: nil
                ),
                podcastTitle: "Sample Podcast",
                playProgress: 0.0,
                status: .none
            ),
            onTap: {},
            onPlay: {},
            onAddToQueue: {},
            onToggleFinished: {}
        )

        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Started Episode",
                    publishedDate: Date(),
                    duration: 2400,
                    artworkURL: nil,
                    description: nil
                ),
                podcastTitle: "Sample Podcast",
                playProgress: 0.35,
                status: .none
            ),
            onTap: {},
            showsArtwork: false
        )
    }
    .listStyle(.plain)
}

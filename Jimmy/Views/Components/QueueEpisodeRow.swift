import SwiftUI

/// One queue row: artwork, a two-line title, "Show · 42 min left · 3d" and, once started, a thin
/// progress line. The episode that is loaded in the player is marked by a `waveform` that animates
/// while it plays.
struct QueueEpisodeRow: View {
    let episode: Episode
    let showTitle: String?
    let showArtworkURL: URL?
    let isCurrent: Bool
    let isPlaying: Bool
    let isEditing: Bool
    let onPlay: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledArtworkSide: CGFloat = 60

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                HStack(alignment: .top) {
                    artwork
                    Spacer(minLength: 0)
                    playButton
                }
                details
            }
            .padding(.vertical, JimmyDesign.Spacing.xs)
        } else {
            HStack(spacing: JimmyDesign.Spacing.md) {
                artwork
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
                playButton
            }
            .padding(.vertical, JimmyDesign.Spacing.xs)
        }
    }

    /// What VoiceOver reads for the row: title, show, time and date, then state.
    var accessibilityText: String {
        var parts = [episode.title] + metadata
        if isCurrent { parts.append(isPlaying ? "Playing" : "Paused") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Pieces

    private var artworkSide: CGFloat { min(scaledArtworkSide, 88) }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: artworkSide * 0.18, style: .continuous)
        return BulletproofAsyncImage(url: episode.artworkURL ?? showArtworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color(uiColor: .secondarySystemFill)
        }
        .frame(width: artworkSide, height: artworkSide)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
            Text(episode.title)
                .font(.headline)
                .foregroundStyle(isPlayed ? .secondary : .primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .multilineTextAlignment(.leading)

            HStack(spacing: JimmyDesign.Spacing.xs) {
                if isCurrent {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying && !reduceMotion)
                }
                Text(metadata.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .font(.footnote)

            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if !isEditing {
            Button(action: onPlay) {
                Image(systemName: isCurrent && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isCurrent && isPlaying ? "Pause" : "Play")
        }
    }

    // MARK: - Data

    private var isPlayed: Bool { episode.status.contains(.played) }

    /// 0 when unstarted, played, or of unknown length; otherwise the fraction listened.
    private var progress: Double {
        guard !isPlayed, let duration = episode.duration, duration > 0 else { return 0 }
        return min(max(episode.playbackPosition / duration, 0), 1)
    }

    /// "Show", "42 min left" (or "58 min", or "Played"), "3d" — whatever is known.
    private var metadata: [String] {
        var parts: [String] = []
        if let showTitle, !showTitle.isEmpty { parts.append(showTitle) }
        if isPlayed {
            parts.append("Played")
        } else if let duration = episode.duration, duration > 0 {
            parts.append(progress > 0
                ? "\(QueueTimeFormat.duration(episode.remainingTime)) left"
                : QueueTimeFormat.duration(duration))
        }
        if let publishedDate = episode.publishedDate {
            parts.append(QueueTimeFormat.age(of: publishedDate))
        }
        return parts
    }
}

/// The queue's time strings: "42 min", "2 h 14 min", and episode ages like "3d" or "Oct 2".
enum QueueTimeFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    static func age(of date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1:
            return "Today"
        case 1..<7:
            return "\(days)d"
        default:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            return sameYear
                ? date.formatted(.dateTime.month(.abbreviated).day())
                : date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}

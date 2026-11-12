import JimmyKit
import SwiftUI

/// The tab bar's bottom accessory. Inline: art, title, play. Expanded adds time left and skip
/// forward. Tapping the art or title opens Now Playing.
struct NativeMiniPlayerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let onTap: () -> Void

    var body: some View {
        if let playback = appModel.playback, let episode = playback.currentEpisode {
            let isExpanded = placement == .expanded
            HStack(spacing: JimmyDesign.Spacing.md) {
                Button(action: onTap) {
                    HStack(spacing: JimmyDesign.Spacing.md) {
                        artwork(episode.artworkURL ?? showArtworkURL(for: episode), side: isExpanded ? 36 : 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(episode.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if isExpanded, let timeLeft = timeLeft(playback) {
                                Text(timeLeft)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Now Playing")

                Button {
                    Task { await playback.togglePlayPause() }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                if isExpanded {
                    Button {
                        Task { await playback.skipForward() }
                    } label: {
                        Image(systemName: "goforward.\(Int(playback.skipForwardInterval))")
                            .font(.title3)
                    }
                    .accessibilityLabel("Skip Forward")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, JimmyDesign.Spacing.lg)
            .popoverTip(MiniPlayerTip(), arrowEdge: .bottom)
        }
    }

    private func artwork(_ url: URL?, side: CGFloat) -> some View {
        BulletproofAsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Color(.secondarySystemFill)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
        .accessibilityHidden(true)
    }

    private func showArtworkURL(for episode: JimmyKit.Episode) -> URL? {
        appModel.podcasts.first { $0.id == episode.podcastID }?.artworkURL
    }

    /// "38 min left", once the length is known.
    private func timeLeft(_ playback: JimmyKit.Playback) -> String? {
        guard let duration = playback.duration, duration > 0 else { return nil }
        return "\(QueueTimeFormat.duration(max(duration - playback.position, 0))) left"
    }
}

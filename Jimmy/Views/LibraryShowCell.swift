import SwiftUI
import JimmyKit

/// One show in the Library grid: its artwork, then title, author and the number of new episodes.
/// No card around it; the artwork is the only shape.
struct LibraryShowCell: View {
    let podcast: JimmyKit.Podcast
    let newEpisodeCount: Int
    let transitionID: String
    let namespace: Namespace.ID

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            artwork
                .padding(.bottom, 6)

            Text(podcast.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)

            Text(podcast.author)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            if newEpisodeCount > 0 {
                Text("\(newEpisodeCount) new")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("^[\(newEpisodeCount) new episode](inflect: true)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
    }

    private var artwork: some View {
        Color(uiColor: .secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                BulletproofAsyncImage(url: podcast.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
            .clipShape(ArtworkShape())
            .matchedTransitionSource(id: transitionID, in: namespace)
            .accessibilityHidden(true)
    }

    /// Per show, the episodes published after it was followed that haven't been started or
    /// finished. A show's back catalog never counts, so a newly followed show starts at zero.
    nonisolated static func newEpisodeCounts(
        episodes: [JimmyKit.EpisodeListItem],
        podcasts: [JimmyKit.Podcast]
    ) -> [UUID: Int] {
        let followedAt = Dictionary(podcasts.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { first, _ in first })
        var counts: [UUID: Int] = [:]
        for item in episodes {
            guard let podcastID = item.episode.podcastID,
                  let followed = followedAt[podcastID],
                  let published = item.episode.publishedDate,
                  published > followed,
                  item.progress?.isFinished != true,
                  (item.progress?.position ?? 0) == 0 else { continue }
            counts[podcastID, default: 0] += 1
        }
        return counts
    }
}

/// Artwork corners: 0.18 of the side, continuous (`docs/design.md`, Radius).
private nonisolated struct ArtworkShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) * 0.18, style: .continuous).path(in: rect)
    }
}

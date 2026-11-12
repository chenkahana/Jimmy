import SwiftUI

/// Artwork, title, author and Follow on the band, then the description in three lines with More.
struct PodcastHeader: View {
    let podcast: Podcast
    let title: String
    let band: ArtworkContrast?
    let isFollowing: Bool
    let isUpdatingFollow: Bool
    let onFollow: () -> Void
    let onUnfollow: (() -> Void)?
    @Binding var isTitleVisible: Bool

    @State private var isDescriptionExpanded = false
    @State private var fullDescriptionHeight: CGFloat = 0
    @State private var shownDescriptionHeight: CGFloat = 0

    private let artworkSide: CGFloat = 200
    private var bandText: Color { band?.text.color ?? .primary }
    private var description: String { podcast.description.cleanedDescription }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: JimmyDesign.Spacing.lg) {
                BulletproofAsyncImage(url: podcast.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    JimmyDesign.Palette.fieldFill
                }
                .frame(width: artworkSide, height: artworkSide)
                .clipShape(RoundedRectangle(cornerRadius: artworkSide * 0.18, style: .continuous))
                .shadow(
                    color: JimmyDesign.Shadow.artworkColor,
                    radius: JimmyDesign.Shadow.artworkRadius,
                    y: JimmyDesign.Shadow.artworkY
                )
                .accessibilityHidden(true)

                VStack(spacing: JimmyDesign.Spacing.xs) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .onScrollVisibilityChange { isTitleVisible = $0 }
                    if !podcast.author.isEmpty {
                        Text(podcast.author)
                            .font(.body)
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(bandText)

                followButton
            }
            .padding(JimmyDesign.Spacing.xl)
            .frame(maxWidth: .infinity)
            .background(band?.color ?? JimmyDesign.Palette.canvas)

            if !description.isEmpty {
                descriptionView
                    .padding(JimmyDesign.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private var followButton: some View {
        if isFollowing {
            Button("Following", systemImage: "checkmark") { onUnfollow?() }
                .buttonStyle(.glass)
                .foregroundStyle(bandText)
                .disabled(onUnfollow == nil)
                .accessibilityHint(onUnfollow == nil ? "" : "Unfollows the show")
        } else {
            Button(action: onFollow) {
                if isUpdatingFollow {
                    ProgressView()
                } else {
                    Label("Follow", systemImage: "plus")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isUpdatingFollow)
        }
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.xs) {
            Text(description)
                .foregroundStyle(.secondary)
                .lineLimit(isDescriptionExpanded ? nil : 3)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { shownDescriptionHeight = $0 })
                .background {
                    Text(description)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height },
                                          action: { fullDescriptionHeight = $0 })
                }

            if isDescriptionExpanded || fullDescriptionHeight > shownDescriptionHeight + 1 {
                Button(isDescriptionExpanded ? "Less" : "More") { isDescriptionExpanded.toggle() }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

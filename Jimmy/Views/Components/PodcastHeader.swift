import SwiftUI

/// The show's artwork as a full-width hero that fades into the page at the top and bottom, then the
/// title, author and Follow, then the description in three lines with More.
struct PodcastHeader: View {
    let podcast: Podcast
    let title: String
    let isFollowing: Bool
    let isUpdatingFollow: Bool
    let onFollow: () -> Void
    let onUnfollow: (() -> Void)?
    @Binding var isTitleVisible: Bool

    @State private var isDescriptionExpanded = false
    @State private var fullDescriptionHeight: CGFloat = 0
    @State private var shownDescriptionHeight: CGFloat = 0

    /// Square on a phone; on wider layouts the art is cropped to this height instead of growing.
    private let maxHeroHeight: CGFloat = 480
    private var description: String { podcast.description.cleanedDescription }

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(spacing: JimmyDesign.Spacing.lg) {
                VStack(spacing: JimmyDesign.Spacing.xs) {
                    Text(title)
                        .font(.title.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .onScrollVisibilityChange { isTitleVisible = $0 }
                    if !podcast.author.isEmpty {
                        Text(podcast.author)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)

                followButton
            }
            .padding(.horizontal, JimmyDesign.Spacing.xl)
            // The title sits on the last, faded stretch of the artwork.
            .padding(.top, -JimmyDesign.Spacing.xxl)

            if !description.isEmpty {
                descriptionView
                    .padding(JimmyDesign.Spacing.lg)
            }
        }
    }

    /// The artwork reaches behind the status bar and navigation bar, fading in from the page at the top
    /// so the bar's buttons stay legible, and out into the page at the bottom.
    private var hero: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: maxHeroHeight)
            .overlay {
                BulletproofAsyncImage(url: podcast.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    JimmyDesign.Palette.fieldFill
                }
            }
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.25), location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.6),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var followButton: some View {
        if isFollowing {
            Button("Following", systemImage: "checkmark") { onUnfollow?() }
                .buttonStyle(.glass)
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

import SwiftUI

private enum DiscoverRowMetrics {
    static let artworkSize: CGFloat = 56
    /// Artwork corners are 0.18 of the side (docs/design.md).
    static let artworkRadius: CGFloat = artworkSize * 0.18
}

/// Subscribe control used across Discover: a plus that becomes a checkmark.
private struct DiscoverSubscribeButton: View {
    let title: String
    let isSubscribed: Bool
    var isProcessing: Bool = false
    let onSubscribe: () -> Void
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Button {
            if !isSubscribed && !isProcessing { onSubscribe() }
        } label: {
            Group {
                if !redactionReasons.isEmpty {
                    // A loading placeholder row has nothing to subscribe to.
                    Color.clear.frame(width: 28, height: 28)
                } else if isProcessing {
                    ProgressView()
                } else {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(isSubscribed ? Color.secondary : Color.accentColor)
                }
            }
            // Inside the label so the whole 44 pt square is the button, not just the glyph.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSubscribed || isProcessing)
        .accessibilityLabel(isSubscribed ? "Subscribed to \(title)" : "Subscribe to \(title)")
    }
}

/// The shared row shape: leading artwork, the titles, and a trailing control. At accessibility text sizes the
/// titles move under the artwork so they keep the full width.
private struct DiscoverRow<Leading: View, Titles: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let leading: Leading
    private let titles: Titles
    private let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder titles: () -> Titles,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.titles = titles()
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                    HStack(spacing: JimmyDesign.Spacing.md) {
                        leading
                        Spacer(minLength: 0)
                        trailing
                    }
                    titles
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            } else {
                HStack(spacing: JimmyDesign.Spacing.md) {
                    leading
                    titles
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .padding(.vertical, JimmyDesign.Spacing.xs)
        .contentShape(Rectangle())
    }
}

private struct DiscoverRowTitles: View {
    let title: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the titles have the full row width, so they wrap instead of truncating.
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(isAccessibilitySize ? nil : 1)
        }
    }
}

/// A Top Shows row: rank, artwork, title and author. The chart is a ranking, so the number is shown.
struct DiscoverTopShowRow: View {
    let index: Int
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        DiscoverRow {
            Text("\(index)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)

            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: DiscoverRowMetrics.artworkSize,
                cornerRadius: DiscoverRowMetrics.artworkRadius
            )
        } titles: {
            DiscoverRowTitles(title: result.title, subtitle: result.author)
        } trailing: {
            DiscoverSubscribeButton(
                title: result.title,
                isSubscribed: isSubscribed,
                isProcessing: isProcessing,
                onSubscribe: onSubscribe
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Number \(index): \(result.title) by \(result.author). \(isSubscribed ? "Subscribed" : "Not subscribed")."
        )
    }
}

struct DiscoverSearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        DiscoverRow {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: DiscoverRowMetrics.artworkSize,
                cornerRadius: DiscoverRowMetrics.artworkRadius
            )
        } titles: {
            DiscoverRowTitles(title: result.title, subtitle: "\(result.author) · \(result.genre)")
        } trailing: {
            DiscoverSubscribeButton(
                title: result.title,
                isSubscribed: isSubscribed,
                isProcessing: isProcessing,
                onSubscribe: onSubscribe
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(result.title) by \(result.author), \(result.genre). \(isSubscribed ? "Subscribed" : "Not subscribed")."
        )
    }
}

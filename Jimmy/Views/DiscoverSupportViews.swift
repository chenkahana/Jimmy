import SwiftUI

/// Subscribe control used across Discover: a plus that becomes a checkmark.
private struct DiscoverSubscribeButton: View {
    let title: String
    let isSubscribed: Bool
    var isProcessing: Bool = false
    let onSubscribe: () -> Void

    var body: some View {
        Button {
            if !isSubscribed && !isProcessing { onSubscribe() }
        } label: {
            if isProcessing {
                ProgressView()
            } else {
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isSubscribed ? Color.secondary : Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(isSubscribed || isProcessing)
        .accessibilityLabel(isSubscribed ? "Subscribed to \(title)" : "Subscribe to \(title)")
    }
}

struct EnhancedFeaturedPodcastCard: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 160,
                cornerRadius: JimmyDesign.Radius.lg
            )

            HStack(alignment: .top, spacing: JimmyDesign.Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(result.author)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                DiscoverSubscribeButton(
                    title: result.title,
                    isSubscribed: isSubscribed,
                    isProcessing: isProcessing,
                    onSubscribe: onSubscribe
                )
            }
        }
        .frame(width: 160)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) by \(result.author). \(isSubscribed ? "Subscribed" : "Not subscribed").")
    }
}

struct EnhancedTrendingEpisodeCard: View {
    let episode: TrendingEpisode
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
            PodcastArtworkView(
                artworkURL: episode.artworkURL,
                size: 140,
                cornerRadius: JimmyDesign.Radius.md
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(episode.podcastName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(episode.title) from \(episode.podcastName)")
        .accessibilityHint("Double tap to view episode details")
    }
}

struct EnhancedTopChartRow: View {
    let index: Int
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: JimmyDesign.Spacing.md) {
            Text("\(index)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)

            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 56,
                cornerRadius: JimmyDesign.Radius.sm
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(result.author)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            DiscoverSubscribeButton(title: result.title, isSubscribed: isSubscribed, onSubscribe: onSubscribe)
        }
        .padding(.vertical, JimmyDesign.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(index): \(result.title) by \(result.author). \(isSubscribed ? "Subscribed" : "Not subscribed").")
    }
}

struct DiscoverSearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: JimmyDesign.Spacing.md) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 56,
                cornerRadius: JimmyDesign.Radius.sm
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text("\(result.author) · \(result.genre)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            DiscoverSubscribeButton(
                title: result.title,
                isSubscribed: isSubscribed,
                isProcessing: isProcessing,
                onSubscribe: onSubscribe
            )
        }
        .padding(.vertical, JimmyDesign.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) by \(result.author), \(result.genre). \(isSubscribed ? "Subscribed" : "Not subscribed").")
    }
}

struct TrendingEpisodeDetailView: View {
    let episode: TrendingEpisode
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PodcastArtworkView(
                    artworkURL: episode.artworkURL,
                    size: 300,
                    cornerRadius: JimmyDesign.Radius.xl
                )
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(episode.podcastName)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Button("Play Episode") {
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Subscribe to Podcast") {
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(20)
        }
        .background(JimmyScreenBackground())
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

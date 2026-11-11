import SwiftUI

struct EnhancedFeaturedPodcastCard: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    private static let colorPairs: [(Color, Color)] = [
        (.pink, .orange),
        (.purple, .blue),
        (.green, .teal),
        (.yellow, .orange),
        (.mint, .green),
        (.cyan, .indigo),
        (.red, .pink),
        (.orange, .pink)
    ]

    private var gradient: LinearGradient {
        let pair = Self.colorPairs[abs(result.id) % Self.colorPairs.count]
        return LinearGradient(
            colors: [pair.0.opacity(0.15), pair.1.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 180,
                cornerRadius: 20
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                    }
                    Text(isProcessing ? "Loading..." : (isSubscribed ? "Subscribed" : "Subscribe"))
                }
                .font(.caption.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            isSubscribed
                            ? LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                        )
                )
                .foregroundColor(isSubscribed ? .green : .accentColor)
                .overlay {
                    Capsule()
                        .stroke(
                            isSubscribed ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.5),
                            lineWidth: 1
                        )
                }
                .opacity((isSubscribed || isProcessing) ? 0.6 : 1.0)
                .onTapGesture {
                    if !isSubscribed && !isProcessing {
                        onSubscribe()
                    }
                }
            }
        }
        .frame(width: 180)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.clear,
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: JimmyDesign.Shadow.cardColor, radius: JimmyDesign.Shadow.cardRadius, x: 0, y: JimmyDesign.Shadow.cardY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) by \(result.author). \(isSubscribed ? "Subscribed" : "Not subscribed").")
        .accessibilityHint(isSubscribed ? "" : "Double tap to subscribe")
    }
}

struct EnhancedTrendingEpisodeCard: View {
    let episode: TrendingEpisode
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                PodcastArtworkView(
                    artworkURL: episode.artworkURL,
                    size: 160,
                    cornerRadius: 16
                )

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text("HOT")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.accentColor, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
                .shadow(color: .accentColor.opacity(0.6), radius: 6, x: 0, y: 3)
                .offset(x: -8, y: 8)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 160)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: JimmyDesign.Shadow.cardColor, radius: JimmyDesign.Shadow.cardRadius, x: 0, y: JimmyDesign.Shadow.cardY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trending: \(episode.title) from \(episode.podcastName)")
        .accessibilityHint("Double tap to view episode details")
    }
}

struct EnhancedTopChartRow: View {
    let index: Int
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Text("\(index)")
                    .font(.headline.bold())
                    .foregroundColor(.accentColor)
            }

            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 70,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                Text(isSubscribed ? "✓" : "+")
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        isSubscribed
                        ? LinearGradient(colors: [.green.opacity(0.3), .green.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .foregroundColor(isSubscribed ? .green : .accentColor)
            .overlay {
                Capsule()
                    .stroke(
                        isSubscribed ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.5),
                        lineWidth: 1
                    )
            }
            .opacity(isSubscribed ? 0.6 : 1.0)
            .onTapGesture {
                if !isSubscribed {
                    onSubscribe()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.clear,
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        )
        .shadow(color: JimmyDesign.Shadow.cardColor, radius: JimmyDesign.Shadow.cardRadius, x: 0, y: JimmyDesign.Shadow.cardY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(index): \(result.title) by \(result.author). \(isSubscribed ? "Subscribed" : "Not subscribed").")
        .accessibilityHint(isSubscribed ? "" : "Double tap to subscribe")
    }
}

struct DiscoverSearchResultRow: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let isProcessing: Bool
    let onSubscribe: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 70,
                cornerRadius: 12
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(result.genre)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)

                    Spacer()

                    HStack(spacing: 4) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                                .font(.caption)
                        }
                        Text(isProcessing ? "Loading..." : (isSubscribed ? "Subscribed" : "Subscribe"))
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        (isSubscribed ? Color.green : Color.accentColor).opacity(0.2)
                    )
                    .foregroundColor(isSubscribed ? Color.green : Color.accentColor)
                    .cornerRadius(10)
                    .opacity((isSubscribed || isProcessing) ? 0.6 : 1.0)
                    .onTapGesture {
                        if !isSubscribed && !isProcessing {
                            onSubscribe()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.clear,
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.6
                        )
                )
        )
        .shadow(color: JimmyDesign.Shadow.cardColor, radius: JimmyDesign.Shadow.cardRadius, x: 0, y: JimmyDesign.Shadow.cardY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) by \(result.author), \(result.genre). \(isSubscribed ? "Subscribed" : "Not subscribed").")
        .accessibilityHint(isSubscribed ? "" : "Double tap to subscribe")
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
                    cornerRadius: 24
                )
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    Text(episode.title)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Text(episode.podcastName)
                        .font(.title3)
                        .foregroundColor(.secondary)

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
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground),
                    Color(.systemBackground).opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

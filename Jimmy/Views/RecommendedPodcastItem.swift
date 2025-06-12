import SwiftUI

struct RecommendedPodcastItem: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    /// Gradient palette for dynamic backgrounds
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
            colors: [pair.0.opacity(0.2), pair.1.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 120,
                cornerRadius: 12
            )
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }

            Text(result.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)

            Button(action: onSubscribe) {
                Text(isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isSubscribed ? Color.green : Color.blue)
                            .opacity(0.2)
                    )
                    .foregroundColor(isSubscribed ? .green : .blue)
                    .cornerRadius(8)
            }
            .disabled(isSubscribed)
        }
        .padding(8)
        .background(gradient)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

#Preview {
    RecommendedPodcastItem(
        result: PodcastSearchResult(
            id: 1,
            title: "Sample Podcast",
            author: "Author",
            feedURL: URL(string: "https://example.com/feed")!,
            artworkURL: nil,
            description: "",
            genre: "",
            trackCount: 0
        ),
        isSubscribed: false,
        onSubscribe: {}
    )
}

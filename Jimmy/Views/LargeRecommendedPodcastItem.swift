import SwiftUI

struct LargeRecommendedPodcastItem: View {
    let result: PodcastSearchResult
    let isSubscribed: Bool
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
            colors: [pair.0.opacity(0.2), pair.1.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PodcastArtworkView(
                artworkURL: result.artworkURL,
                size: 160,
                cornerRadius: 16
            )
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
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
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Button(action: onSubscribe) {
                Text(isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        (isSubscribed ? Color.green : Color.blue)
                            .opacity(0.2)
                    )
                    .foregroundColor(isSubscribed ? .green : .blue)
                    .cornerRadius(10)
            }
            .disabled(isSubscribed)
        }
        .padding(8)
        .background(gradient)
        .enhanced3DCard(cornerRadius: 20, elevation: 3)
    }
}

#Preview {
    LargeRecommendedPodcastItem(
        result: PodcastSearchResult(
            id: 1,
            title: "Sample Podcast",
            author: "Author",
            feedURL: URL(string: "https://example.com/feed")!,
            artworkURL: nil,
            description: "",
            genre: "News",
            trackCount: 0
        ),
        isSubscribed: false,
        onSubscribe: {}
    )
}

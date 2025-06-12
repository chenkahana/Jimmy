import SwiftUI

/// A view that displays a single episode in a list.
///
/// This view is designed to be a simple, reusable component that displays the
/// information for a single episode. It is driven by the `Episode` model and
/// uses `AsyncImage` for performant image loading.
struct EpisodeRowView: View {
    
    let episode: Episode
    let podcast: Podcast?
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode artwork with podcast fallback
            AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Episode details
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(episode.description ?? "No description available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                
                if let publishedDate = episode.publishedDate {
                    Text(publishedDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Play status indicator
            if episode.played {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
#Preview {
    EpisodeRowView(
        episode: Episode(
            id: UUID(),
            title: "Sample Episode Title",
            artworkURL: nil,
            audioURL: nil,
            description: "This is a sample episode description that shows how the episode row will look in the app.",
            played: false,
            podcastID: UUID(),
            publishedDate: Date(),
            localFileURL: nil,
            playbackPosition: 0,
            duration: 3600
        ),
        podcast: nil
    )
    .padding()
}

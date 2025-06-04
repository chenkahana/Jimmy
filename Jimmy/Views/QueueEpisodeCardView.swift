import SwiftUI

struct QueueEpisodeCardView: View {
    let episode: Episode
    let podcast: Podcast?
    let isCurrentlyPlaying: Bool
    let isEditMode: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onMoveToEnd: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: isCurrentlyPlaying ?
                                [Color.orange.opacity(0.3), Color.orange.opacity(0.1)] :
                                [Color(.systemGray5), Color(.systemGray4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: isCurrentlyPlaying ? "speaker.wave.2.fill" : "waveform.circle")
                            .foregroundColor(isCurrentlyPlaying ? .orange : .gray)
                            .font(.title2)
                    )
            }
            .transition(.opacity.combined(with: .scale))
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                isCurrentlyPlaying ?
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 2)
                    : nil
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(episode.title)
                    .font(.system(.body, design: .rounded, weight: isCurrentlyPlaying ? .semibold : .medium))
                    .foregroundColor(isCurrentlyPlaying ? .orange : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let description = episode.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack {
                    if let publishedDate = episode.publishedDate {
                        Text(publishedDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let podcast = podcast {
                        Text("• \(podcast.title)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 18, height: 2.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onTap()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isEditMode {
                Button {
                    onMoveToEnd()
                } label: {
                    Label("Move", systemImage: "arrow.down.to.line")
                }
                .tint(.green)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash.fill")
                }
            }
        }
    }
}

#Preview {
    let sampleEpisode = Episode(
        id: UUID(),
        title: "Sample Episode Title That Might Be Long",
        artworkURL: nil,
        audioURL: nil,
        description: "This is a sample description for the episode that shows how the text wraps and displays in the card.",
        played: false,
        podcastID: UUID(),
        publishedDate: Date(),
        localFileURL: nil,
        playbackPosition: 0
    )

    let samplePodcast = Podcast(
        id: UUID(),
        title: "Sample Podcast",
        author: "Author Name",
        description: "Description",
        feedURL: URL(string: "https://example.com/feed")!
    )

    return QueueEpisodeCardView(
        episode: sampleEpisode,
        podcast: samplePodcast,
        isCurrentlyPlaying: false,
        isEditMode: true,
        onTap: {},
        onRemove: {},
        onMoveToEnd: {}
    )
    .padding()
}

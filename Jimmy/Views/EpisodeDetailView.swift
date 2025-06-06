import SwiftUI

struct EpisodeDetailView: View {
    let episode: Episode
    let podcast: Podcast
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    
    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    // Header section with episode info
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            // Episode artwork
                            CachedAsyncImage(url: episode.artworkURL ?? podcast.artworkURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "play.circle")
                                            .font(.title)
                                            .foregroundColor(.gray)
                                    )
                            }
                            .transition(.opacity.combined(with: .scale))
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            
                            // Episode info
                            VStack(alignment: .leading, spacing: 8) {
                                Text(episode.title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                
                                Text(podcast.title)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                
                                // Episode metadata
                                VStack(alignment: .leading, spacing: 4) {
                                    if let date = episode.publishedDate {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    // Episode status
                                    HStack(spacing: 8) {
                                        if episode.played {
                                            Label("Played", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else if episode.playbackPosition > 0 {
                                            Label("In Progress", systemImage: "clock.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                        
                                        // Currently playing indicator
                                        if audioPlayer.currentEpisode?.id == episode.id {
                                            Label("Now Playing", systemImage: "speaker.wave.2.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        
                        // Action buttons
                        HStack(spacing: 16) {
                            // Play/Pause button
                            Button(action: {
                                if audioPlayer.currentEpisode?.id == episode.id {
                                    audioPlayer.togglePlayPause()
                                } else {
                                    // Load and play this episode using new queue logic
                                    QueueViewModel.shared.playEpisodeFromLibrary(episode)
                                }
                            }) {
                                HStack {
                                    Image(systemName: (audioPlayer.currentEpisode?.id == episode.id && audioPlayer.isPlaying) ? "pause.fill" : "play.fill")
                                    Text((audioPlayer.currentEpisode?.id == episode.id && audioPlayer.isPlaying) ? "Pause" : "Play")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange)
                                .cornerRadius(8)
                            }
                            
                            // Add to Queue button
                            Button(action: {
                                QueueViewModel.shared.addToQueue(episode)
                                FeedbackManager.shared.addedToQueue()
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle")
                                    Text("Queue")
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .background(Color(.systemBackground))
                    
                    Divider()
                        .padding(.top, 8)
                    
                    // Episode description section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Episode Details")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        if let description = episode.description, !description.isEmpty {
                            Text(description)
                                .font(.body)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No description available for this episode.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        // Additional episode info
                        VStack(alignment: .leading, spacing: 12) {
                            if episode.playbackPosition > 0 {
                                HStack {
                                    Text("Progress:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(formatTime(episode.playbackPosition))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let audioURL = episode.audioURL {
                                HStack {
                                    Text("Audio URL:")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(audioURL.host ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Bottom padding for mini player
                    Spacer()
                        .frame(height: 100)
                }
            .navigationTitle("Episode Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            // Play Next
                            QueueViewModel.shared.addToTopOfQueue(episode)
                            FeedbackManager.shared.playNext()
                        }) {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        
                        Button(action: {
                            // Toggle played status
                            EpisodeViewModel.shared.markEpisodeAsPlayed(episode, played: !episode.played)
                        }) {
                            Label(
                                episode.played ? "Mark as Unplayed" : "Mark as Played",
                                systemImage: episode.played ? "checkmark.circle" : "checkmark.circle.fill"
                            )
                        }
                        
                        Divider()

                        Button(action: {
                            shareEpisode()
                        }) {
                            Label("Share Episode", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval.truncatingRemainder(dividingBy: 3600)) / 60
        let seconds = Int(timeInterval.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func shareEpisode() {
        AppleEpisodeLinkService.shared.fetchAppleLink(for: episode, podcast: podcast) { url in
            if let url = url {
                shareURL = url
                showingShareSheet = true
            }
        }
    }
}

#Preview {
    let samplePodcast = Podcast(
        id: UUID(),
        title: "Sample Podcast Show",
        author: "Podcast Author",
        description: "This is a sample podcast description.",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        artworkURL: nil
    )
    
    let sampleEpisode = Episode(
        id: UUID(),
        title: "Episode 1: Introduction to SwiftUI and Modern iOS Development",
        artworkURL: nil,
        audioURL: URL(string: "https://example.com/audio.mp3"),
        description: """
        In this comprehensive episode, we dive deep into the world of SwiftUI and modern iOS development. We'll explore the fundamentals of declarative UI programming, discuss best practices for building responsive and accessible applications, and walk through practical examples that you can apply to your own projects.
        
        Topics covered in this episode:
        • Introduction to SwiftUI's declarative syntax
        • Understanding state management with @State, @Binding, and @ObservedObject
        • Building reusable UI components
        • Implementing navigation and view transitions
        • Accessibility considerations in SwiftUI
        • Performance optimization techniques
        
        Whether you're new to iOS development or transitioning from UIKit, this episode provides valuable insights and practical knowledge to help you build better apps with SwiftUI.
        """,
        played: false,
        podcastID: samplePodcast.id,
        publishedDate: Date(),
        localFileURL: nil,
        playbackPosition: 1245
    )
    
    EpisodeDetailView(episode: sampleEpisode, podcast: samplePodcast)
} 
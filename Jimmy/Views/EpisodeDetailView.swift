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
                headerSection
                Divider().padding(.top, 8)
                descriptionSection
                Spacer().frame(height: 100)
            }
        }
        .navigationTitle("Episode Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                shareButton
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareURL = shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            episodeInfoRow
            actionButtons
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var episodeInfoRow: some View {
        HStack(spacing: 16) {
            episodeArtwork
            episodeInfo
        }
    }
    
    private var episodeArtwork: some View {
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
    }
    
    private var episodeInfo: some View {
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
            
            episodeMetadata
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var episodeMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let date = episode.publishedDate {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            episodeStatusRow
        }
    }
    
    private var episodeStatusRow: some View {
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
            
            if audioPlayer.currentEpisode?.id == episode.id {
                Label("Now Playing", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            playButton
            queueButton
        }
        .padding(.horizontal)
    }
    
    private var playButton: some View {
        Button(action: {
            if audioPlayer.currentEpisode?.id == episode.id {
                audioPlayer.togglePlayPause()
            } else {
                DispatchQueue.main.async {
                    Task {
                        await QueueViewModel.shared.playEpisode(episode)
                    }
                }
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
    }
    
    private var queueButton: some View {
        Button(action: {
            Task {
                try? await QueueViewModel.shared.addEpisode(episode)
            }
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
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Episode Details")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            episodeDescription
            additionalInfo
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var episodeDescription: some View {
        Group {
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
        }
    }
    
    private var additionalInfo: some View {
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
    
    private var shareButton: some View {
        Menu {
            shareMenuItems
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
    
    private var shareMenuItems: some View {
        Group {
            Button(action: {
                shareEpisode()
            }) {
                Label("Share Episode", systemImage: "square.and.arrow.up")
            }
            
            Button(action: {
                if let url = episode.audioURL {
                    UIPasteboard.general.url = url
                }
            }) {
                Label("Copy Audio URL", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                // Mark as played/unplayed
                togglePlayedStatus()
            }) {
                Label(episode.played ? "Mark as Unplayed" : "Mark as Played", 
                      systemImage: episode.played ? "circle" : "checkmark.circle")
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

    private func togglePlayedStatus() {
        // Toggle the played status of the episode
        Task {
            let viewModel = EpisodeDetailViewModel(episode: episode)
            if episode.played {
                await viewModel.markAsUnplayed()
            } else {
                await viewModel.markAsPlayed()
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
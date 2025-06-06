import SwiftUI

struct EpisodeRowView: View {
    let episode: Episode
    let podcast: Podcast
    let isCurrentlyPlaying: Bool
    let onTap: () -> Void
    let onPlayNext: ((Episode) -> Void)?
    let onMarkAsPlayed: ((Episode, Bool) -> Void)?
    
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @ObservedObject private var loadingManager = LoadingStateManager.shared
    @State private var showingEpisodeDetail = false
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    
    init(episode: Episode, podcast: Podcast, isCurrentlyPlaying: Bool, onTap: @escaping () -> Void, onPlayNext: ((Episode) -> Void)? = nil, onMarkAsPlayed: ((Episode, Bool) -> Void)? = nil) {
        self.episode = episode
        self.podcast = podcast
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.onTap = onTap
        self.onPlayNext = onPlayNext
        self.onMarkAsPlayed = onMarkAsPlayed
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Episode artwork with enhanced 3D styling and played indicator overlay
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: episode.artworkURL ?? podcast.artworkURL) { image in
                    image
                        .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.gray.opacity(0.4),
                                        Color.gray.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Image(systemName: "play.circle")
                                    .foregroundColor(.gray)
                                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                            )
                    }
                    .transition(.opacity.combined(with: .scale))
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(episode.played ? 0.6 : 1.0) // Dim played episodes
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
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
                    
                    // Enhanced played indicator with 3D effect
                    if episode.played {
                        ZStack {
                            // Enhanced background circle with gradient
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white,
                                            Color.white.opacity(0.9)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 20, height: 20)
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                            
                            // Green checkmark with subtle shadow
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.green)
                                .shadow(color: .green.opacity(0.3), radius: 1, x: 0, y: 0.5)
                        }
                        .offset(x: 6, y: 6)
                    }
                }
                
                // Episode information
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(
                            isCurrentlyPlaying ? .orange : 
                            episode.played ? .secondary : .primary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .opacity(episode.played ? 0.7 : 1.0) // Dim played episode titles
                    
                    if let description = episode.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .opacity(episode.played ? 0.6 : 1.0) // Dim played episode descriptions
                    }
                    
                    HStack {
                        // Publication date
                        if let date = episode.publishedDate {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .opacity(episode.played ? 0.6 : 1.0)
                        }
                        
                        Spacer()
                        
                        // Episode status indicators
                        HStack(spacing: 8) {
                            // Progress indicator for unplayed episodes with progress
                            if episode.playbackPosition > 0 && !episode.played {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    
                                    // Show remaining time if we have duration info, otherwise show elapsed time
                                    if episode.episodeDuration > 0 {
                                        let remainingTime = episode.episodeDuration - episode.playbackPosition
                                        Text("\(formatRemainingTime(remainingTime)) left")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                    } else {
                                        Text(formatTime(episode.playbackPosition))
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            }
                            
                            // Played status badge with remaining time for partially completed episodes
                            if episode.played {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    
                                    // Show completion info for played episodes that might have some time left
                                    if episode.episodeDuration > 0 {
                                        let remainingTime = episode.episodeDuration - episode.playbackPosition
                                        if remainingTime > 60 { // More than 1 minute left
                                            Text("\(formatRemainingTime(remainingTime)) left")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                                .fontWeight(.medium)
                                        } else {
                                            Text("Played")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                                .fontWeight(.medium)
                                        }
                                    } else {
                                        Text("Played")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Options button and play button
                VStack {
                    // Options menu button - larger touch target and contextual menu
                    Menu {
                        Button(action: {
                            addToQueue()
                        }) {
                            Label("Add to Queue", systemImage: "plus.circle")
                        }
                        
                        Button(action: {
                            playNext()
                        }) {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        
                        Button(action: {
                            togglePlayedStatus()
                        }) {
                            Label(
                                episode.played ? "Mark as Unplayed" : "Mark as Played",
                                systemImage: episode.played ? "checkmark.circle" : "checkmark.circle.fill"
                            )
                        }
                        
                        Divider()

                        Button(action: {
                            showingEpisodeDetail = true
                        }) {
                            Label("Episode Details", systemImage: "info.circle")
                        }

                        Button(action: {
                            shareEpisode()
                        }) {
                            Label("Share Episode", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44) // Larger touch target (44pt minimum recommended)
                            .background(
                                Circle()
                                    .fill(Color.clear)
                                    .contentShape(Circle()) // Ensure the entire circle area is tappable
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Play button - separate from main tap area
                    Button(action: {
                        // This actually plays the episode
                        if !loadingManager.isEpisodeLoading(episode.id) {
                            onTap()
                        }
                    }) {
                        Group {
                            if loadingManager.isEpisodeLoading(episode.id) {
                                LoadingIndicator(size: 20, color: .blue)
                            } else {
                                Image(systemName: isCurrentlyPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(isCurrentlyPlaying ? .orange : .blue)
                                    .opacity(episode.played ? 0.7 : 1.0) // Slightly dim play button for played episodes
                            }
                        }
                        .frame(width: 44, height: 44) // Also improve play button touch target
                        .background(
                            Circle()
                                .fill(Color.clear)
                                .contentShape(Circle())
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(loadingManager.isEpisodeLoading(episode.id))
                }
                .frame(height: 60)
            }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .enhanced3DListRow(isSelected: isCurrentlyPlaying)
        .onTapGesture {
            showingEpisodeDetail = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                addToQueue()
            } label: {
                Label("Queue", systemImage: "plus.circle")
            }
            .tint(.blue)

            Button {
                playNext()
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(.green)

            Button {
                togglePlayedStatus()
            } label: {
                Label(episode.played ? "Mark Unplayed" : "Mark Played",
                      systemImage: episode.played ? "checkmark.circle" : "checkmark.circle.fill")
            }
            .tint(episode.played ? .orange : .gray)
        }
        .sheet(isPresented: $showingEpisodeDetail) {
            NavigationView {
                EpisodeDetailView(episode: episode, podcast: podcast)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    private func addToQueue() {
        queueViewModel.addToQueue(episode)
        
        // Show haptic feedback
        FeedbackManager.shared.addedToQueue()
    }
    
    private func playNext() {
        // Insert at the beginning of the queue for "play next" functionality
        queueViewModel.addToTopOfQueue(episode)
        
        onPlayNext?(episode)
        
        // Show haptic feedback
        FeedbackManager.shared.playNext()
    }
    
    private func togglePlayedStatus() {
        onMarkAsPlayed?(episode, !episode.played)

        // Show haptic feedback
        FeedbackManager.shared.markAsPlayed()
    }

    private func shareEpisode() {
        AppleEpisodeLinkService.shared.fetchAppleLink(for: episode, podcast: podcast) { url in
            if let url = url {
                shareURL = url
                showingShareSheet = true
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
    
    private func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let totalMinutes = Int(timeInterval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
}

#Preview {
    let samplePodcast = Podcast(
        id: UUID(),
        title: "Sample Podcast",
        author: "Author",
        description: "This is a sample podcast description.",
        feedURL: URL(string: "https://example.com/feed.xml")!,
        artworkURL: nil
    )
    
    let sampleEpisode = Episode(
        id: UUID(),
        title: "Episode 1: Introduction to SwiftUI",
        artworkURL: nil,
        audioURL: nil,
        description: "In this episode we discuss the basics of SwiftUI and how to build beautiful user interfaces.",
        played: false,
        podcastID: samplePodcast.id,
        publishedDate: Date(),
        localFileURL: nil,
        playbackPosition: 0,
        duration: 2700 // 45 minute episode
    )
    
    VStack {
        EpisodeRowView(
            episode: sampleEpisode,
            podcast: samplePodcast,
            isCurrentlyPlaying: false,
            onTap: { },
            onPlayNext: { _ in },
            onMarkAsPlayed: { _, _ in }
        )
        .padding()
        
        EpisodeRowView(
            episode: Episode(
                id: UUID(),
                title: "Episode 2: Advanced SwiftUI Concepts",
                artworkURL: nil,
                audioURL: nil,
                description: "Deep dive into advanced SwiftUI concepts including state management and animations.",
                played: false,
                podcastID: samplePodcast.id,
                publishedDate: Date().addingTimeInterval(-86400),
                localFileURL: nil,
                playbackPosition: 1245,
                duration: 3600 // 1 hour episode
            ),
            podcast: samplePodcast,
            isCurrentlyPlaying: true,
            onTap: { },
            onPlayNext: { _ in },
            onMarkAsPlayed: { _, _ in }
        )
        .padding()
        
        Spacer()
    }
} 
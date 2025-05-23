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
    @State private var showingEpisodeDetail = false
    @State private var dragOffset = CGSize.zero
    @State private var isShowingSwipeOptions = false
    
    init(episode: Episode, podcast: Podcast, isCurrentlyPlaying: Bool, onTap: @escaping () -> Void, onPlayNext: ((Episode) -> Void)? = nil, onMarkAsPlayed: ((Episode, Bool) -> Void)? = nil) {
        self.episode = episode
        self.podcast = podcast
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.onTap = onTap
        self.onPlayNext = onPlayNext
        self.onMarkAsPlayed = onMarkAsPlayed
    }
    
    var body: some View {
        ZStack {
            // Background swipe options
            HStack {
                Spacer()
                
                if isShowingSwipeOptions {
                    // Quick action buttons revealed by swipe
                    HStack(spacing: 12) {
                        // Add to Queue button
                        Button(action: {
                            addToQueue()
                            withAnimation(.spring(response: 0.3)) {
                                resetSwipeState()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                Text("Add to\nQueue")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundColor(.white)
                            .frame(width: 60, height: 80)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        
                        // Mark as Played button
                        Button(action: {
                            togglePlayedStatus()
                            withAnimation(.spring(response: 0.3)) {
                                resetSwipeState()
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: episode.played ? "checkmark.circle" : "checkmark.circle.fill")
                                    .font(.title2)
                                Text(episode.played ? "Mark\nUnplayed" : "Mark\nPlayed")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundColor(.white)
                            .frame(width: 60, height: 80)
                            .background(episode.played ? Color.orange : Color.green)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }
            
            // Main episode content
            HStack(spacing: 12) {
                // Episode artwork with played indicator overlay
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: episode.artworkURL ?? podcast.artworkURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "play.circle")
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .opacity(episode.played ? 0.6 : 1.0) // Dim played episodes
                    
                    // Enhanced played indicator
                    if episode.played {
                        ZStack {
                            // White background circle for contrast
                            Circle()
                                .fill(Color.white)
                                .frame(width: 20, height: 20)
                            
                            // Green checkmark
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        .offset(x: 6, y: 6)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
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
                                    Text(formatTime(episode.playbackPosition))
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            }
                            
                            // Played status badge
                            if episode.played {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    Text("Played")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
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
                        onTap()
                    }) {
                        Image(systemName: isCurrentlyPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(isCurrentlyPlaying ? .orange : .blue)
                            .opacity(episode.played ? 0.7 : 1.0) // Slightly dim play button for played episodes
                            .frame(width: 44, height: 44) // Also improve play button touch target
                            .background(
                                Circle()
                                    .fill(Color.clear)
                                    .contentShape(Circle())
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 60)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isCurrentlyPlaying ? Color.orange.opacity(0.1) : 
                        episode.played ? Color.gray.opacity(0.05) : Color(.systemBackground)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isCurrentlyPlaying ? Color.orange.opacity(0.3) : 
                        episode.played ? Color.gray.opacity(0.1) : Color.clear, 
                        lineWidth: 1
                    )
            )
            .offset(x: dragOffset.width)
            .onTapGesture {
                if isShowingSwipeOptions {
                    // If swipe options are showing, reset them
                    withAnimation(.spring(response: 0.3)) {
                        resetSwipeState()
                    }
                } else {
                    // Otherwise, show episode detail
                    showingEpisodeDetail = true
                }
            }
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow left swipe (negative values)
                        if value.translation.width < 0 {
                            let clampedX = max(value.translation.width, -140) // Limit swipe distance
                            dragOffset = CGSize(width: clampedX, height: 0)
                            
                            // Show options when swiped enough
                            if clampedX < -60 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowingSwipeOptions = true
                                }
                            }
                        }
                    }
                    .onEnded { value in
                        let threshold: CGFloat = -80
                        
                        if value.translation.width < threshold {
                            // Keep options visible
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = CGSize(width: -140, height: 0)
                                isShowingSwipeOptions = true
                            }
                        } else {
                            // Reset to original position
                            withAnimation(.spring(response: 0.3)) {
                                resetSwipeState()
                            }
                        }
                    }
            )
        }
        .fullScreenCover(isPresented: $showingEpisodeDetail) {
            EpisodeDetailView(episode: episode, podcast: podcast)
        }
    }
    
    private func resetSwipeState() {
        dragOffset = .zero
        isShowingSwipeOptions = false
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
        playbackPosition: 0
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
                played: true,
                podcastID: samplePodcast.id,
                publishedDate: Date().addingTimeInterval(-86400),
                localFileURL: nil,
                playbackPosition: 1245
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
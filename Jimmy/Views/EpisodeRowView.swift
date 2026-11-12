import SwiftUI

/// A view that displays a single episode in a list.
///
/// This view is designed to be a simple, reusable component that displays the
/// information for a single episode. It is driven by the `Episode` model and
/// uses `AsyncImage` for performant image loading.
struct EpisodeRowView: View {
    
    let episodeWithState: EpisodeWithPlaybackState
    var podcastArtworkURL: URL? = nil
    @State private var dragOffset: CGFloat = 0
    @StateObject private var swipeStateManager = SwipeStateManager.shared
    
    private var isShowingActions: Bool {
        swipeStateManager.isShowingActions(for: episodeWithState.episode.id)
    }
    
    // Swipe action callbacks
    var onPlay: (() -> Void)?
    var onAddToQueue: (() -> Void)?
    var onToggleFinished: (() -> Void)?
    
    private let actionWidth: CGFloat = 60
    private let maxSwipeDistance: CGFloat = 130 // 2 actions * 60pt + spacing
    
    var body: some View {
        ZStack {
            // Background actions (revealed when swiping)
            HStack(spacing: 0) {
                Spacer()
                swipeActionsView
            }
            
            // Main episode content
            episodeContent
                .offset(x: dragOffset)
                .simultaneousGesture(swipeGesture)
        }
        .animation(.motion, value: dragOffset) // spring animation refactored
        .onChange(of: swipeStateManager.isShowingActions(for: episodeWithState.episode.id)) { isShowing in
            if !isShowing && dragOffset != 0 {
                withAnimation(.motion) {
                    dragOffset = 0
                }
            }
        }
        .episodeContextMenu(
            episode: episodeWithState.episode,
            episodeWithState: episodeWithState,
            onAddToQueue: { onAddToQueue?() },
            onMarkAsPlayed: { onToggleFinished?() },
            onPlayNext: { addToQueueNext() },
            onShare: { shareEpisode() }
        )
    }
    
    private var episodeContent: some View {
        HStack(spacing: 12) {
            // Episode artwork - slightly smaller to make room for more content
            EpisodeArtworkView(
                episodeArtworkURL: episodeWithState.episode.artworkURL,
                podcastArtworkURL: podcastArtworkURL,
                size: 56
            )
            
            // Episode information - optimized layout
            VStack(alignment: .leading, spacing: 4) {
                // Title and status row
                HStack(alignment: .top, spacing: 8) {
                    Text(episodeWithState.episode.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .lineLimit(3)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer(minLength: 4)
                    
                    // Status indicators
                    HStack(spacing: 4) {
                        if episodeWithState.playbackState.finished {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        // Duration
                        if let duration = episodeWithState.episode.duration, duration > 0 {
                            Text(formatDuration(Int(duration)))
                                .font(.system(.caption2, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.1))
                                )
                        }
                    }
                }
                
                // Description - more compact
                if let description = episodeWithState.episode.description, !description.isEmpty {
                    Text(description.cleanedDescription)
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // Progress bar (if episode has been started but not finished)
                if episodeWithState.playbackState.position > 0 && !episodeWithState.playbackState.finished,
                   let episodeDuration = episodeWithState.episode.duration, episodeDuration > 0 {
                    let progress = Double(episodeWithState.playbackState.position) / Double(episodeDuration)

                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(formatDuration(Int(episodeWithState.playbackState.position)))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(Int(progress * 100))% complete")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                            .scaleEffect(y: 0.8)
                            .accessibilityLabel("Playback progress")
                            .accessibilityValue("\(Int(progress * 100))% complete")
                    }
                }
                
                // Date and additional metadata
                HStack(spacing: 8) {
                    if let publishedDate = episodeWithState.episode.publishedDate {
                        Text(publishedDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Add file size if available
                    if let audioURL = episodeWithState.episode.audioURL {
                        Text("• MP3")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Play status text
                    if episodeWithState.playbackState.finished {
                        Text("Played")
                            .font(.system(.caption2, weight: .medium))
                            .foregroundColor(.green)
                    } else if episodeWithState.playbackState.position > 0 {
                        Text("In Progress")
                            .font(.system(.caption2, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Play button - more compact
            Button(action: {
                onPlay?()
            }) {
                Image(systemName: episodeWithState.playbackState.position > 0 && !episodeWithState.playbackState.finished ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(episodeWithState.episode.title)")
            .accessibilityHint(episodeWithState.playbackState.position > 0 && !episodeWithState.playbackState.finished ? "Resume from \(formatDuration(Int(episodeWithState.playbackState.position)))" : "Double tap to play")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            JimmyDesign.Palette.canvasElevated,
            in: RoundedRectangle(cornerRadius: JimmyDesign.Radius.lg, style: .continuous)
        )
        .opacity(episodeWithState.playbackState.finished ? 0.8 : 1.0)
        .statusBadge(for: episodeWithState.episode)
    }
    
    private var swipeActionsView: some View {
        HStack(spacing: 8) {
            // Queue Action
            SwipeActionButton(
                icon: "arrow.down.to.line",
                title: "Queue",
                width: actionWidth,
                color: .blue
            ) {
                onAddToQueue?()
                resetSwipe()
            }
            
            // Mark as Played/Unplayed Action
            SwipeActionButton(
                icon: episodeWithState.playbackState.finished ? "circle" : "checkmark.circle.fill",
                title: episodeWithState.playbackState.finished ? "Unplayed" : "Played",
                width: actionWidth,
                color: .orange
            ) {
                onToggleFinished?()
                resetSwipe()
            }
        }
        .opacity(isShowingActions ? 1.0 : 0.0)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation
                
                // Much more restrictive conditions for swipe activation
                // Require horizontal movement to be at least 3x vertical movement
                // AND require significant horizontal movement (50+ points)
                let isHorizontalSwipe = abs(translation.width) > abs(translation.height) * 3
                let hasSignificantHorizontalMovement = abs(translation.width) > 50
                
                guard isHorizontalSwipe && hasSignificantHorizontalMovement else {
                    return // Prioritize vertical scrolling
                }
                
                // Only allow left swipe (negative translation)
                if translation.width < 0 {
                    let progress = min(abs(translation.width), maxSwipeDistance)
                    dragOffset = -progress
                    
                    // Show swipe actions if dragged far enough
                    if progress > 60 {
                        swipeStateManager.closeAllSwipeActions()
                        swipeStateManager.setShowingActions(for: episodeWithState.episode.id)
                    }
                }
                // Remove right swipe resistance to avoid interfering with scrolling
            }
            .onEnded { value in
                let translation = value.translation
                let velocity = value.velocity
                
                // Only process if it was a very clear horizontal swipe
                let isHorizontalSwipe = abs(translation.width) > abs(translation.height) * 3
                let hasSignificantHorizontalMovement = abs(translation.width) > 50
                
                guard isHorizontalSwipe && hasSignificantHorizontalMovement else {
                    resetSwipe()
                    return
                }
                
                if translation.width < 0 {
                    // Require more deliberate action to show swipe actions
                    let shouldShowActions = abs(translation.width) > 100 || velocity.width < -800
                    
                    withAnimation(.motion) { // spring animation refactored
                        if shouldShowActions {
                            // Close any other open swipe actions first
                            swipeStateManager.closeAllSwipeActions()
                            dragOffset = -maxSwipeDistance
                            swipeStateManager.setShowingActions(for: episodeWithState.episode.id)
                        } else {
                            resetSwipe()
                        }
                    }
                } else {
                    resetSwipe()
                }
            }
    }
    
    private func resetSwipe() {
        withAnimation(.motion) { // spring animation refactored
            dragOffset = 0
            swipeStateManager.closeSwipeActions(for: episodeWithState.episode.id)
        }
    }
    
    // MARK: - Context Menu Actions
    
    private func addToQueueNext() {
        Task {
            await AppModel.current?.playNext(episodeWithState.episode.id)
        }
    }
    
    private func shareEpisode() {
        // Share functionality will be handled by the context menu modifier
    }
    
    // Helper function to format duration
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return String(format: "%d:%02d:00", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}

// MARK: - Episode Artwork View

struct EpisodeArtworkView: View {
    let episodeArtworkURL: URL?
    let podcastArtworkURL: URL?
    let size: CGFloat
    
    // Prioritize episode artwork, fallback to podcast artwork
    // This ensures episode-specific artwork is shown when available
    private var stableArtworkURL: URL? {
        episodeArtworkURL ?? podcastArtworkURL
    }
    
    var body: some View {
        BulletproofAsyncImage(url: stableArtworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            placeholderView
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .id(stableArtworkURL?.absoluteString ?? "placeholder") // Stable ID to prevent unnecessary reloads
    }
    
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(.gray.opacity(0.6))
            )
    }
}

// MARK: - Swipe Action Button

struct SwipeActionButton: View {
    let icon: String
    let title: String
    let width: CGFloat
    let color: Color
    let action: () -> Void
    
    init(icon: String, title: String, width: CGFloat, color: Color = .blue, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.width = width
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
            Motion.mediumHaptic() // haptic feedback added
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: width, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        // Episode with its own artwork (should prioritize episode artwork)
        EpisodeRowView(
            episodeWithState: EpisodeWithPlaybackState(
                episode: Episode(
                    id: UUID(),
                    title: "Episode with Custom Artwork",
                    podcastID: UUID(),
                    publishedDate: Date(),
                    duration: 3600,
                    artworkURL: URL(string: "https://example.com/episode-artwork.jpg"), // Episode-specific artwork
                    description: "This episode has its own custom artwork that should be displayed.",
                    audioURL: URL(string: "https://example.com/audio.mp3")
                ),
                playbackState: PlaybackState(
                    episodeID: UUID(),
                    position: 0,
                    finished: true,
                    updatedAt: Date()
                )
            ),
            podcastArtworkURL: URL(string: "https://example.com/podcast-artwork.jpg") // Podcast fallback
        )
        
        // Episode without artwork (should fallback to podcast artwork)
        EpisodeRowView(
            episodeWithState: EpisodeWithPlaybackState(
                episode: Episode(
                    id: UUID(),
                    title: "Episode Using Podcast Artwork",
                    podcastID: UUID(),
                    publishedDate: Date().addingTimeInterval(-86400),
                    duration: 2400,
                    artworkURL: nil, // No episode artwork
                    description: "This episode will use the podcast's artwork as fallback.",
                    audioURL: URL(string: "https://example.com/audio2.mp3")
                ),
                playbackState: PlaybackState(
                    episodeID: UUID(),
                    position: 1200,
                    finished: false,
                    updatedAt: Date()
                )
            ),
            podcastArtworkURL: URL(string: "https://example.com/podcast-artwork.jpg") // Will be used as fallback
        )
    }
    .padding()
}

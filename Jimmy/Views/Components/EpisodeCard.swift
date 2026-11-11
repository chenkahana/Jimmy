import SwiftUI

/// Unified Episode Card component that consolidates three duplicate episode cells
/// Follows iOS 26 Liquid Glass design language with consistent badge logic
struct EpisodeCard: View, Equatable {
    let episode: EpisodeWithStatus
    let onTap: () -> Void
    let onPlay: (() -> Void)?
    let onAddToQueue: (() -> Void)?
    let onToggleFinished: (() -> Void)?

    // Queue-specific actions
    let onRemoveFromQueue: (() -> Void)?
    let onMoveToLast: (() -> Void)?
    let queuePosition: Int?

    @ObservedObject private var audioPlayer = AudioPlayerService.shared

    private var isActuallyPlaying: Bool {
        audioPlayer.isPlaying && audioPlayer.currentEpisode?.id == episode.id
    }

    init(
        episode: EpisodeWithStatus,
        onTap: @escaping () -> Void,
        onPlay: (() -> Void)? = nil,
        onAddToQueue: (() -> Void)? = nil,
        onToggleFinished: (() -> Void)? = nil,
        onRemoveFromQueue: (() -> Void)? = nil,
        onMoveToLast: (() -> Void)? = nil,
        queuePosition: Int? = nil
    ) {
        self.episode = episode
        self.onTap = onTap
        self.onPlay = onPlay
        self.onAddToQueue = onAddToQueue
        self.onToggleFinished = onToggleFinished
        self.onRemoveFromQueue = onRemoveFromQueue
        self.onMoveToLast = onMoveToLast
        self.queuePosition = queuePosition
    }

    // Swipe action state
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingHorizontally: Bool = false
    @StateObject private var swipeStateManager = SwipeStateManager.shared
    
    private var showingActions: Bool {
        swipeStateManager.isShowingActions(for: episode.id)
    }
    
    @State private var isPressed = false

    private let actionWidth: CGFloat = 60
    private let maxSwipeDistance: CGFloat = 130
    
    var body: some View {

        ZStack {
            // Background actions (revealed when swiping)
            HStack(spacing: 0) {
                Spacer()
                swipeActionsView
            }
            
            // Main episode content
            cardContent
                .offset(x: dragOffset)
                .simultaneousGesture(swipeGesture)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 10) {
                    // Trigger haptic feedback
                    Motion.rigidHaptic() // haptic feedback refactored
                } onPressingChanged: { pressing in
                    withAnimation(.motionMicro) { // spring animation refactored
                        isPressed = pressing
                    }
                }
        }
        // ANIMATION FIX: Single animation for swipe offset only
        .animation(.motion, value: dragOffset) // spring animation refactored
        .onChange(of: swipeStateManager.isShowingActions(for: episode.id)) { isShowing in
            if !isShowing && dragOffset != 0 {
                withAnimation(.motion) {
                    dragOffset = 0
                }
            }
        }
        .onTapGesture {
            // Close all swipe actions when navigating
            swipeStateManager.closeAllSwipeActions()
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var label = episode.title
            if !episode.podcastTitle.isEmpty {
                label += ", \(episode.podcastTitle)"
            }
            if episode.duration > 0 {
                label += ", \(formatDuration(Int(episode.duration)))"
            }
            if episode.playProgress > 0 {
                label += ", \(Int(episode.playProgress * 100))% played"
            }
            return label
        }())
        .accessibilityHint(isActuallyPlaying ? "Currently playing" : "Double tap to open episode")
    }
    
    private var cardContent: some View {
        HStack(alignment: .center, spacing: 12) {
            // Episode artwork - centered and enlarged
            EpisodeArtwork(
                episodeArtworkURL: episode.artworkURL,
                podcastArtworkURL: episode.podcastArtworkURL,
                size: 90
            )
            
            // Main content area
            VStack(alignment: .leading, spacing: 6) {
                // Top section: Episode title and description
                VStack(alignment: .leading, spacing: 4) {
                    // Episode title
                    Text(episode.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold)) // Made smaller
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    // Description
                    if let description = episode.description, !description.isEmpty {
                        Text(description.cleanedDescription)
                            .font(.system(.caption2, design: .default)) // Made smaller
                            .foregroundColor(.secondary)
                            .lineLimit(2) // Allow 2 lines as requested
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                    }
                }
                
                Spacer()
                
                // Bottom section: Progress bar, date/time, status badge, and ellipsis menu
                VStack(alignment: .leading, spacing: 4) {
                    PremiumProgressBar(progress: episode.playProgress, height: 3)
                    
                    // Bottom row: Date/time on left, status badge and ellipsis on right
                    HStack {
                        // Date and duration
                        HStack(spacing: 4) {
                            if let publishedDate = episode.publishedDate {
                                Text(formatRelativeDate(publishedDate))
                                    .font(.system(.caption2, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            if episode.duration > 0 {
                                Text("•")
                                    .font(.system(.caption2, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                                
                                Text(formatDuration(Int(episode.duration)))
                                    .font(.system(.caption2, design: .default, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Status badge and ellipsis menu in bottom right
                        HStack(spacing: 8) {
                            // Status badge - use EpisodeBadges like QueueEpisodeCard
                            EpisodeBadges(status: episode.status)
                            
                            // Ellipsis context menu
                            Menu {
                                if let onPlay = onPlay {
                                    Button(action: onPlay) {
                                        Label("Play", systemImage: "play.fill")
                                    }
                                }
                                if let onAddToQueue = onAddToQueue {
                                    Button(action: onAddToQueue) {
                                        Label("Add to Queue", systemImage: "plus.circle")
                                    }
                                }
                                Button(action: {
                                    let shareText = "\(episode.title) — \(episode.podcastTitle)"
                                    let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let rootVC = windowScene.windows.first?.rootViewController {
                                        rootVC.present(activityVC, animated: true)
                                    }
                                }) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                if let onToggleFinished = onToggleFinished {
                                    Button(action: onToggleFinished) {
                                        Label(episode.status == .played ? "Mark as Unplayed" : "Mark as Played", systemImage: episode.status == .played ? "circle" : "checkmark.circle.fill")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .accessibilityLabel("More options for \(episode.title)")
                            .accessibilityHint("Double tap to open episode options")
                        }
                    }
                }
            }
        }
        .frame(minHeight: 80)
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .padding(.vertical, 10)
        .opacity(episode.status == .played ? 0.7 : 1.0)
        .saturation(episode.status == .played ? 0.5 : 1.0)
        .jimmyCard(isHighlighted: isActuallyPlaying)
        .nowPlayingGlow(isPlaying: isActuallyPlaying)
        .contentShape(Rectangle())
    }
    
    private var swipeActionsView: some View {
        HStack(spacing: 8) {
            // Queue-specific actions (when in queue)
            if let onMoveToLast = onMoveToLast {
                SwipeActionButton(
                    icon: "arrow.down.to.line",
                    title: "Last",
                    width: actionWidth,
                    color: .gray,
                    action: {
                        onMoveToLast()
                        resetSwipe()
                    }
                )
            }
            
            if let onRemoveFromQueue = onRemoveFromQueue {
                SwipeActionButton(
                    icon: "trash.fill",
                    title: "Remove",
                    width: actionWidth,
                    color: .gray,
                    action: {
                        onRemoveFromQueue()
                        resetSwipe()
                    }
                )
            }
            
            // Regular actions (when not in queue)
            if onRemoveFromQueue == nil && onMoveToLast == nil {
                // Queue Action
                if let onAddToQueue = onAddToQueue {
                    SwipeActionButton(
                        icon: "arrow.down.to.line",
                        title: "Queue",
                        width: actionWidth,
                        color: .gray,
                        action: {
                            onAddToQueue()
                            resetSwipe()
                        }
                    )
                }
                
                // Mark as Played/Unplayed Action
                if let onToggleFinished = onToggleFinished {
                    SwipeActionButton(
                        icon: episode.status == .played ? "circle" : "checkmark.circle.fill",
                        title: episode.status == .played ? "Unplayed" : "Played",
                        width: actionWidth,
                        color: .gray,
                        action: {
                            onToggleFinished()
                            resetSwipe()
                        }
                    )
                }
            }
        }
        .opacity(showingActions ? 1.0 : 0.0)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let translation = value.translation

                // On first meaningful movement, lock direction
                // Only claim leftward drags — rightward drags fall through
                // to NavigationStack's swipe-back gesture
                if !isDraggingHorizontally {
                    if abs(translation.width) > abs(translation.height) && translation.width < 0 {
                        isDraggingHorizontally = true
                    } else {
                        return // vertical or rightward drag — let parent handle it
                    }
                }

                if translation.width < 0 {
                    dragOffset = max(-maxSwipeDistance, translation.width)
                }
            }
            .onEnded { value in
                let translation = value.translation.width

                if isDraggingHorizontally && translation < -60 {
                    // Show actions
                    swipeStateManager.closeAllSwipeActions()
                    dragOffset = -maxSwipeDistance
                    swipeStateManager.setShowingActions(for: episode.id)
                } else {
                    // Reset
                    resetSwipe()
                }
                isDraggingHorizontally = false
            }
    }
    
    private func resetSwipe() {
        withAnimation(.motion) { // spring animation refactored
            dragOffset = 0
            swipeStateManager.closeSwipeActions(for: episode.id)
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Equatable
    static func == (lhs: EpisodeCard, rhs: EpisodeCard) -> Bool {
        lhs.episode.id == rhs.episode.id &&
        lhs.episode.status == rhs.episode.status &&
        lhs.episode.playProgress == rhs.episode.playProgress
    }
}

// MARK: - Episode Artwork Component
struct EpisodeArtwork: View {
    let episodeArtworkURL: URL?
    let podcastArtworkURL: URL?
    let size: CGFloat
    
    var body: some View {
        BulletproofAsyncImage(url: episodeArtworkURL ?? podcastArtworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.3))
                        .foregroundColor(.secondary.opacity(0.6))
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}




// MARK: - Episode Badges Component
struct EpisodeBadges: View {
    let status: EpisodeCardStatus
    
    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .playing:
                PlayingBadge()
            case .queued:
                QueuedBadge()
            case .played:
                PlayedBadge()
            case .none:
                EmptyView()
            }
        }
    }
}

struct PlayingBadge: View {
    var body: some View {
        AnimatedWaveformBars(barCount: 3, color: .accentColor, size: 12)
    }
}

struct QueuedBadge: View {
    var body: some View {
        Image(systemName: "list.bullet")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
    }
}

struct PlayedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
    }
}

// Note: Using existing SwipeActionButton from EpisodeRowView.swift

// Note: cleanedDescription extension already exists in StringExtensions.swift

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Sample Episode Title That Might Be Long",
                    publishedDate: Date(),
                    duration: 3600,
                    artworkURL: nil,
                    description: "This is a sample episode description that shows how the card handles longer text content."
                ),
                podcastTitle: "Sample Podcast",
                playProgress: 0.0,
                status: .none
            ),
            onTap: {},
            onPlay: {},
            onAddToQueue: {},
            onToggleFinished: {}
        )
        
        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Currently Playing Episode",
                    publishedDate: Date(),
                    duration: 2400,
                    artworkURL: nil,
                    description: "This episode is currently being played."
                ),
                podcastTitle: "Active Podcast",
                playProgress: 0.35,
                status: .playing
            ),
            onTap: {},
            onPlay: {},
            onAddToQueue: {},
            onToggleFinished: {}
        )
        
        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Queued Episode",
                    publishedDate: Date(),
                    duration: 1800,
                    artworkURL: nil,
                    description: "This episode is in the queue."
                ),
                podcastTitle: "Queue Podcast",
                playProgress: 0.0,
                status: .queued
            ),
            onTap: {},
            onPlay: {},
            onAddToQueue: {},
            onToggleFinished: {}
        )
        
        EpisodeCard(
            episode: EpisodeWithStatus(
                episode: Episode(
                    id: UUID(),
                    title: "Completed Episode",
                    publishedDate: Date(),
                    duration: 3000,
                    artworkURL: nil,
                    description: "This episode has been played completely."
                ),
                podcastTitle: "Finished Podcast",
                playProgress: 1.0,
                status: .played
            ),
            onTap: {},
            onPlay: {},
            onAddToQueue: {},
            onToggleFinished: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
} 

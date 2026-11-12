import SwiftUI
import JimmyKit

/// Queue-specific episode card with drag reordering and queue-specific swipe actions
struct QueueEpisodeCard: View {
    let episode: EpisodeWithStatus
    let isCurrentlyPlaying: Bool
    let isEditMode: Bool
    var isProminent: Bool = false
    var downloadState: JimmyKit.DownloadState? = nil

    // Actions
    let onTap: () -> Void
    let onPlay: () -> Void
    let onRemove: () -> Void
    let onMoveToTop: () -> Void
    let onMoveToBottom: () -> Void
    let onToggleFinished: () -> Void
    var onDownload: () -> Void = {}
    var onCancelDownload: () -> Void = {}
    var onDeleteDownload: () -> Void = {}

    // Gesture state
    @State private var swipeOffset: CGFloat = 0
    @State private var isPressed = false
    @State private var isDraggingHorizontally: Bool = false
    @StateObject private var swipeStateManager = SwipeStateManager.shared

    private var showingActions: Bool {
        swipeStateManager.isShowingActions(for: episode.id)
    }

    // Constants
    private let swipeThreshold: CGFloat = 60
    private let actionWidth: CGFloat = 55
    /// Revealed swipe offset for the three action buttons (download/cancel/delete, move to last,
    /// remove) at `actionWidth` each, with `HStack`'s 8pt spacing between them.
    private var revealedOffset: CGFloat { -(actionWidth * 3 + 16) }
    
    var body: some View {
        ZStack {
            // Background swipe actions
            HStack(spacing: 0) {
                Spacer()
                swipeActionsView
            }
            
            // Main card content
            cardContent
                .offset(x: swipeOffset)
                .scaleEffect(isPressed ? 1.03 : 1.0)
                .shadow(color: .black.opacity(isPressed ? 0.2 : 0), radius: isPressed ? 24 : 0, x: 0, y: 8)
                .zIndex(isPressed ? 1 : 0)
                .simultaneousGesture(swipeGesture)
                .onTapGesture {
                    if !isEditMode && !showingActions {
                        // Close all swipe actions when navigating
                        swipeStateManager.closeAllSwipeActions()
                        onTap()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 10) {
                    // Haptic feedback for long press
                    Motion.mediumHaptic() // haptic feedback refactored
                } onPressingChanged: { pressing in
                    withAnimation(.motionMicro) { // spring animation refactored
                        isPressed = pressing
                    }
                }
        }
        // ANIMATION FIX: Single animation for swipe offset only
        .animation(.motion, value: swipeOffset) // spring animation refactored
        .onChange(of: swipeStateManager.isShowingActions(for: episode.id)) { isShowing in
            if !isShowing && swipeOffset != 0 {
                withAnimation(.motion) {
                    swipeOffset = 0
                }
            }
        }
    }
    
    private var cardContent: some View {
        HStack(spacing: 12) {
            // Drag handle (only visible in edit mode)
            if isEditMode {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.secondary)
                    .frame(width: 20)
            }
            

            
            // Episode artwork (larger for prominent/Up Next cards)
            EpisodeArtwork(
                episodeArtworkURL: episode.artworkURL,
                podcastArtworkURL: episode.podcastArtworkURL,
                size: isProminent ? 72 : 56
            )
            
            // Episode information
            VStack(alignment: .leading, spacing: 4) {
                // Episode title and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if let description = episode.description, !description.isEmpty {
                        Text(description.cleanedDescription)
                            .font(.system(.caption, design: .default))
                            .foregroundColor(.secondary)
                            .lineLimit(isProminent ? 3 : 2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                // Progress bar for partially played episodes
                if episode.playProgress > 0 && episode.status != .played {
                    progressBar
                }
            }
            
            Spacer()
            
            // Status badges and play button
            VStack(alignment: .trailing, spacing: 8) {
                EpisodeBadges(status: episode.status)
                
                if !isEditMode {
                    playButton
                }
            }
        }
        .frame(minHeight: isProminent ? 90 : 80)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isCurrentlyPlaying ? Color.accentColor.opacity(0.3) : .white.opacity(0.1), lineWidth: isCurrentlyPlaying ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .nowPlayingGlow(isPlaying: isCurrentlyPlaying)
        .opacity(episode.status == .played ? 0.7 : 1.0)
    }
    

    
    private var progressBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(formatDuration(Int(episode.duration * episode.playProgress)))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(episode.playProgress * 100))% complete")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }

            PremiumProgressBar(progress: episode.playProgress, height: 3)
        }
    }
    
    private var playButton: some View {
        Button(action: onPlay) {
            Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
    }
    
    private var swipeActionsView: some View {
        HStack(spacing: 8) {
            // Move to Last
            QueueSwipeActionButton(
                icon: "arrow.down.to.line",
                title: "Last",
                width: actionWidth,
                color: .green,
                action: {
                    onMoveToBottom()
                    resetSwipe()
                }
            )

            downloadSwipeActionButton

            // Remove from Queue
            QueueSwipeActionButton(
                icon: "trash.fill",
                title: "Remove",
                width: actionWidth,
                color: .red,
                action: {
                    onRemove()
                    resetSwipe()
                }
            )
        }
        .opacity(showingActions ? 1.0 : 0.0)
    }

    @ViewBuilder
    private var downloadSwipeActionButton: some View {
        switch downloadState {
        case nil, .failed:
            QueueSwipeActionButton(
                icon: "arrow.down.circle.fill",
                title: "Download",
                width: actionWidth,
                color: .blue,
                action: {
                    onDownload()
                    resetSwipe()
                }
            )
        case .queued, .downloading:
            QueueSwipeActionButton(
                icon: "xmark.circle.fill",
                title: "Cancel",
                width: actionWidth,
                color: .orange,
                action: {
                    onCancelDownload()
                    resetSwipe()
                }
            )
        case .done:
            QueueSwipeActionButton(
                icon: "trash.fill",
                title: "Delete",
                width: actionWidth,
                color: .red,
                action: {
                    onDeleteDownload()
                    resetSwipe()
                }
            )
        }
    }
    
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let translation = value.translation

                // On first meaningful movement, lock direction
                if !isDraggingHorizontally {
                    if abs(translation.width) > abs(translation.height) {
                        isDraggingHorizontally = true
                    } else {
                        return // vertical drag — let ScrollView handle it
                    }
                }

                if translation.width < 0 && !isEditMode {
                    swipeOffset = max(revealedOffset, translation.width)
                    if abs(swipeOffset) > 30 && !showingActions {
                        swipeStateManager.closeAllSwipeActions()
                        swipeStateManager.setShowingActions(for: episode.id)
                    }
                }
            }
            .onEnded { value in
                let translation = value.translation.width

                if isDraggingHorizontally && translation < -swipeThreshold && !isEditMode {
                    // Show actions
                    swipeStateManager.closeAllSwipeActions()
                    swipeOffset = revealedOffset
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
            swipeOffset = 0
            swipeStateManager.closeSwipeActions(for: episode.id)
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        } else {
            return "\(minutes)m"
        }
    }
}

/// Queue-specific swipe action button component
struct QueueSwipeActionButton: View {
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
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(width: width, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let sampleEpisode = EpisodeWithStatus(
        episode: Episode(
            id: UUID(),
            title: "Sample Episode",
            podcastID: UUID(),
            publishedDate: Date(),
            duration: 3600,
            artworkURL: nil,
            description: "Sample description",
            audioURL: nil
        ),
        podcastTitle: "Sample Podcast",
        playProgress: 0.3,
        status: .queued,
        podcastArtworkURL: nil
    )
    
    QueueEpisodeCard(
        episode: sampleEpisode,
        isCurrentlyPlaying: false,
        isEditMode: false,
        isProminent: true,
        onTap: {},
        onPlay: {},
        onRemove: {},
        onMoveToTop: {},
        onMoveToBottom: {},
        onToggleFinished: {}
    )
    .padding()
} 
import SwiftUI

struct QueueEpisodeCardView: View {
    let episode: Episode
    let podcast: Podcast?
    let isCurrentlyPlaying: Bool
    let isEditMode: Bool
    let isSwipeOpen: Bool // Whether this specific row should show swipe actions
    let onTap: () -> Void
    let onRemove: () -> Void
    let onMoveToEnd: () -> Void
    let onSwipeOpen: () -> Void // Called when this row opens its swipe actions
    let onSwipeClose: () -> Void // Called when this row closes its swipe actions
    
    @State private var offset: CGFloat = 0
    @State private var dragGestureActive = false
    @State private var isInDeleteZone = false // Track if we're in delete threshold
    
    private let buttonWidth: CGFloat = 60 // Reduced from 80
    private let totalButtonWidth: CGFloat = 120 // Reduced from 160 (Two buttons)
    private let deleteThreshold: CGFloat = 150 // Distance to trigger auto-delete
    
    var body: some View {
        ZStack {
            // Background buttons that appear when swiping (only in normal mode)
            if !isEditMode && isSwipeOpen {
                HStack(spacing: 0) {
                    Spacer()
                    
                    // Move to end button (now first)
                    Button(action: {
                        withAnimation(.spring()) {
                            onMoveToEnd()
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text("Move")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.green)
                    }
                    
                    // Remove button (now second)
                    Button(action: {
                        withAnimation(.spring()) {
                            onRemove()
                        }
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text("Remove")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .frame(width: buttonWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color.accentColor)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Main card content
            HStack(spacing: 16) {
                // Episode Image
                AsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
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
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    isCurrentlyPlaying ? 
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 2)
                    : nil
                )
                
                // Centered content (Episode title, description, date)
                VStack(alignment: .leading, spacing: 6) {
                    // Episode title
                    Text(episode.title)
                        .font(.system(.body, design: .rounded, weight: isCurrentlyPlaying ? .semibold : .medium))
                        .foregroundColor(isCurrentlyPlaying ? .orange : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Description
                    if let description = episode.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Date and podcast info
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
                
                // Drag handles (three horizontal strips) - Always visible
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
                    .fill(isInDeleteZone ? Color.red : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .overlay(
                // Delete zone indicator
                isInDeleteZone ? 
                VStack {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Release to delete")
                        .font(.caption)
                        .foregroundColor(.white)
                        .bold()
                }
                : nil
            )
            .offset(x: isEditMode ? 0 : offset) // Disable offset in edit mode
            .contentShape(Rectangle())
            .onTapGesture {
                // Only handle tap if we're not in edit mode and not in middle of gesture
                guard !isEditMode && !dragGestureActive else { return }
                
                if isSwipeOpen {
                    // Close swipe actions
                    withAnimation(.spring()) {
                        offset = 0
                        onSwipeClose()
                    }
                } else {
                    onTap()
                }
            }
            .simultaneousGesture(
                // Only add swipe gesture when NOT in edit mode
                isEditMode ? nil : DragGesture(coordinateSpace: .local)
                    .onChanged { gesture in
                        let translation = gesture.translation.width
                        let verticalTranslation = abs(gesture.translation.height)
                        
                        // Only handle horizontal swipes (not vertical scrolling)
                        if abs(translation) > verticalTranslation && abs(translation) > 10 {
                            dragGestureActive = true
                            if translation < 0 { // Only allow left swipe
                                offset = max(translation, -deleteThreshold)
                                
                                // Update delete zone state
                                let newDeleteZone = abs(translation) > deleteThreshold * 0.8
                                if newDeleteZone != isInDeleteZone {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isInDeleteZone = newDeleteZone
                                    }
                                }
                                
                                // Open swipe actions when reaching button threshold during drag
                                if abs(translation) > totalButtonWidth/3 && !isSwipeOpen {
                                    onSwipeOpen()
                                }
                            }
                        }
                    }
                    .onEnded { gesture in
                        let translation = gesture.translation.width
                        let velocity = gesture.velocity.width
                        let verticalTranslation = abs(gesture.translation.height)
                        
                        // Only complete swipe if it's clearly horizontal
                        if abs(translation) > verticalTranslation && dragGestureActive {
                            if isInDeleteZone || translation < -deleteThreshold * 0.8 || velocity < -1000 {
                                // Smooth delete animation - slide out completely then remove
                                withAnimation(.easeOut(duration: 0.3)) {
                                    offset = -UIScreen.main.bounds.width // Slide completely off screen
                                }
                                
                                // Remove item after animation completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onRemove()
                                }
                            } else if translation < -totalButtonWidth/3 {
                                // Show buttons: any significant swipe should show buttons
                                withAnimation(.spring()) {
                                    offset = -totalButtonWidth
                                    isInDeleteZone = false
                                    if !isSwipeOpen {
                                        onSwipeOpen() // Open this row and close others
                                    }
                                }
                            } else {
                                // Close: insufficient swipe
                                withAnimation(.spring()) {
                                    offset = 0
                                    isInDeleteZone = false
                                    onSwipeClose() // Close this row
                                }
                            }
                        } else {
                            // Not a valid horizontal swipe, reset
                            withAnimation(.spring()) {
                                offset = 0
                                isInDeleteZone = false
                                if isSwipeOpen {
                                    onSwipeClose()
                                }
                            }
                        }
                        
                        // Reset drag state after a short delay to allow tap gesture to work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            dragGestureActive = false
                        }
                    }
            )
            .onChange(of: isEditMode) { _, newValue in
                if newValue {
                    // Reset swipe when entering edit mode
                    withAnimation(.spring()) {
                        offset = 0
                        isInDeleteZone = false
                        onSwipeClose()
                    }
                }
            }
            .onChange(of: isSwipeOpen) { _, newValue in
                if !newValue && !dragGestureActive {
                    // Reset offset when swipe is closed externally, but not during active dragging
                    withAnimation(.spring()) {
                        offset = 0
                        isInDeleteZone = false
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        isSwipeOpen: false,
        onTap: {},
        onRemove: {},
        onMoveToEnd: {},
        onSwipeOpen: {},
        onSwipeClose: {}
    )
    .padding()
} 
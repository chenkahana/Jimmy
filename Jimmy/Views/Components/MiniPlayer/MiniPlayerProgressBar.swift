import SwiftUI

/// 2-pixel progress bar that sits above card like top stroke in tab bar
/// Now interactive with long-press and drag gestures for scrubbing
struct MiniPlayerProgressBar: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @Environment(\.nowPlayingNamespace) private var namespace
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isLongPressing = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                PremiumProgressBar(
                    progress: audioPlayer.duration > 0 ? (isDragging ? dragProgress / audioPlayer.duration : audioPlayer.playbackPosition / audioPlayer.duration) : 0,
                    height: 4
                )

                // Invisible drag area for better touch target
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        // Long press gesture to enable dragging
                        LongPressGesture(minimumDuration: 0.3)
                            .onChanged { _ in
                                isLongPressing = true
                                // Medium haptic feedback when long press is recognized
                                Motion.mediumHaptic() // haptic feedback refactored
                            }
                            .onEnded { _ in
                                // Keep long press active for subsequent drag
                            }
                    )
                    .simultaneousGesture(
                        // Drag gesture that only works after long press
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Only allow dragging if long press was detected
                                guard isLongPressing else { return }
                                
                                if !isDragging {
                                    isDragging = true
                                    // Light haptic feedback when starting to drag
                                    Motion.lightHaptic() // haptic feedback refactored
                                }
                                
                                // Calculate progress based on drag position
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                dragProgress = progress * audioPlayer.duration
                            }
                            .onEnded { value in
                                // Only seek if we were actually dragging
                                if isDragging && isLongPressing {
                                    // Seek to the dragged position
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    let seekTime = progress * audioPlayer.duration
                                    audioPlayer.seek(to: seekTime)
                                    
                                    // Selection haptic feedback when releasing
                                    Motion.selectionHaptic() // haptic feedback refactored
                                }
                                
                                // Reset states
                                isDragging = false
                                isLongPressing = false
                            }
                    )
                    .frame(height: 20) // Larger touch target
            }
        }
        .frame(height: 4)
        .if(namespace != nil) { view in
            view.matchedGeometryEffect(id: NowPlayingGeometryID.progress, in: namespace!)
        }
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int(progressPercentage))% complete")
        .accessibilityHint("Long press and drag to scrub through the episode")
    }
    
    private var progressPercentage: Double {
        guard audioPlayer.duration > 0 else { return 0 }
        let currentProgress = isDragging ? dragProgress : audioPlayer.playbackPosition
        return (currentProgress / audioPlayer.duration) * 100
    }
} 
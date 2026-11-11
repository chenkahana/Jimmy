import SwiftUI

/// Glass card that hosts artwork, labels, progress bar & controls
struct MiniPlayerCard: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @StateObject private var colorExtractor = ArtworkColorExtractor.shared
    @State private var dragOffset: CGSize = .zero
    @State private var breathingShadow = false
    
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    // Tab bar height reference - 50pt from LiquidGlassTabBar
    private let tabBarHeight: CGFloat = 50
    private var cardHeight: CGFloat { tabBarHeight * 1.6 } // Increased from 1.2 to 1.6 (80pt)
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main card content with internal progress bar and time indicators
                HStack(spacing: 12) {
                    MiniPlayerArtwork()
                    
                    // Title + progress bar + time indicators stack
                    VStack(alignment: .leading, spacing: 3) {
                        MiniPlayerInfoStack()
                        
                        // Progress bar
                        MiniPlayerProgressBar()
                        
                        // Time indicators below progress bar
                        HStack {
                            Text(formatTime(audioPlayer.playbackPosition))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundColor(.primary.opacity(0.7))
                            
                            Spacer()
                            
                            Text(formatTime(audioPlayer.duration))
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .foregroundColor(.primary.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    MiniPlayerControls()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(height: cardHeight)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(colorExtractor.dominantColor.opacity(0.08))
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial).opacity(0.95)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(breathingShadow ? 0.4 : 0.2), radius: 16, x: 0, y: 8)
                )
                .onAppear {
                    if audioPlayer.isPlaying {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            breathingShadow = true
                        }
                    }
                }
                .onChange(of: audioPlayer.isPlaying) { _, playing in
                    if playing {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            breathingShadow = true
                        }
                    } else {
                        breathingShadow = false
                    }
                }
                .overlay(alignment: .topTrailing) {
                    MiniPlayerDismissButton(onDismiss: onDismiss)
                        .offset(x: 8, y: -8)
                }
                .offset(y: dragOffset.height)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Now Playing")
                .accessibilityHint("Double tap to open full player")
                .accessibilityAddTraits(.isButton)
                .onTapGesture {
                    onTap()
                    Motion.mediumHaptic() // haptic feedback added
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow downward drag
                            if value.translation.height > 0 {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 20 {
                                onDismiss()
                            }
                            dragOffset = .zero
                        }
                )
                .animation(.motion, value: dragOffset) // spring animation refactored
            }
        }
        .frame(height: cardHeight)
        .padding(.horizontal, 24) // Match tab bar padding
        .padding(.bottom, 10) // Match tab bar bottom padding
    }
    
    // MARK: - Helper Functions
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
} 
import SwiftUI

/// Play/Pause button only (←/→ seek removed for minimalism)
struct MiniPlayerControls: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    var body: some View {
        Button(action: {
            audioPlayer.togglePlayPause()
            Motion.mediumHaptic() // haptic feedback added
        }) {
            ZStack {
                // Button background with liquid glass effect
                Circle()
                    .fill(.ultraThinMaterial).opacity(0.95) // Match tab bar transparency
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1) // Match tab bar border
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2) // Subtle shadow for button
                
                // Play/pause icon
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.accentColor)
                    .offset(x: audioPlayer.isPlaying ? 0 : 1) // Slight offset for play icon
                    .animation(.motionGentle, value: audioPlayer.isPlaying) // spring animation refactored
            }
        }
        .buttonStyle(MiniPlayerButtonStyle())
        .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
        .accessibilityHint("Double tap to \(audioPlayer.isPlaying ? "pause" : "play") the episode")
    }
}

/// Custom button style for mini-player controls
private struct MiniPlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.motionMicro, value: configuration.isPressed) // spring animation refactored
    }
} 
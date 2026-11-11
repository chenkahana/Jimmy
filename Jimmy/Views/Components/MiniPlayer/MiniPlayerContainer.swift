import SwiftUI

/// Entry point for the new Liquid Glass mini-player
/// Decides when to show, handles hide/show animations
struct MiniPlayerContainer: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var isMiniPlayerHidden = false
    
    let currentTab: Int
    let onTap: () -> Void
    
    var body: some View {
        Group {
            if shouldShowMiniPlayer {
                MiniPlayerCard(
                    onTap: onTap,
                    onDismiss: {
                        withAnimation(.motionTransition) { // spring animation refactored
                            isMiniPlayerHidden = true
                        }
                        Motion.lightHaptic() // haptic feedback added
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                    removal: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom))
                ))
            }
        }
        .onChange(of: audioPlayer.currentEpisode?.id) { _, _ in
            // Reset hidden state when episode changes
            isMiniPlayerHidden = false
        }
        .onChange(of: currentTab) { _, newTab in
            // Reset hidden state when tab changes
            isMiniPlayerHidden = false
        }
    }
    
    private var shouldShowMiniPlayer: Bool {
        audioPlayer.currentEpisode != nil &&
        !isMiniPlayerHidden
    }
} 
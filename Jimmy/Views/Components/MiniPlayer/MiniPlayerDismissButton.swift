import SwiftUI

/// Small "×" pill anchored top-right
struct MiniPlayerDismissButton: View {
    let onDismiss: () -> Void
    
    var body: some View {
        Button(action: {
            onDismiss()
            Motion.lightHaptic() // haptic feedback added
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(6)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial).opacity(0.95)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(DismissButtonStyle())
        .accessibilityLabel("Dismiss mini player")
        .accessibilityHint("Double tap to hide the mini player for this session")
    }
}

/// Custom button style for dismiss button
private struct DismissButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.motionMicro, value: configuration.isPressed) // spring animation refactored
    }
} 
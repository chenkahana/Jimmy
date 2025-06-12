import SwiftUI

/// A 3D button style with depth and shadow effects
struct Enhanced3DButtonStyle: ButtonStyle {
    let depth: CGFloat
    
    init(depth: CGFloat = 2) {
        self.depth = depth
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(
                color: .black.opacity(0.2),
                radius: depth * 2,
                x: 0,
                y: depth
            )
            .shadow(
                color: .black.opacity(0.1),
                radius: depth,
                x: 0,
                y: depth / 2
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
} 
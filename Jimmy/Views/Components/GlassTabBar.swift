import SwiftUI

/// SwiftUI wrapper that overlays a glass-material rounded rectangle behind the system tab bar
struct GlassTabBar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main content
                content
                
                // Glass tab bar overlay
                VStack {
                    Spacer()
                    
                    // Glass background container
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Material.glassCompatible)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(
                            color: Color.black.opacity(0.15),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                        .frame(height: tabBarHeight)
                        .padding(.horizontal, 16)
                        .padding(.bottom, safeAreaBottomPadding(geometry) + 6)
                }
            }
        }
    }
    
    /// Tab bar height constant
    private var tabBarHeight: CGFloat {
        return 83 // Standard tab bar height
    }
    
    /// Calculate safe area bottom padding
    private func safeAreaBottomPadding(_ geometry: GeometryProxy) -> CGFloat {
        return geometry.safeAreaInsets.bottom
    }
} 
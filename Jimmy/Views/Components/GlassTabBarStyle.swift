import SwiftUI

/// ViewModifier that applies glass tab bar styling
struct GlassTabBarStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        GlassTabBar {
            content
        }
    }
}

extension View {
    /// Applies glass tab bar styling to the view
    func glassTabBarStyle() -> some View {
        modifier(GlassTabBarStyleModifier())
    }
} 
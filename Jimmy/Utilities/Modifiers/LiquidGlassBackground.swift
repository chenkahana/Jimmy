import SwiftUI

/// Liquid Glass background modifier following iOS 26 design language
struct LiquidGlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    let shadowOpacity: Double
    let material: Material
    
    init(
        cornerRadius: CGFloat = 16,
        shadowOpacity: Double = 0.15,
        material: Material = .glassCompatible
    ) {
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.material = material
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(shadowOpacity), radius: 20, x: 0, y: 8)
                    .shadow(color: .black.opacity(shadowOpacity * 0.3), radius: 4, x: 0, y: 2)
            )
    }
}

extension View {
    /// Apply Liquid Glass background effect
    func liquidGlassBackground(
        cornerRadius: CGFloat = 16,
        shadowOpacity: Double = 0.15,
        material: Material = .glassCompatible
    ) -> some View {
        modifier(LiquidGlassBackground(
            cornerRadius: cornerRadius,
            shadowOpacity: shadowOpacity,
            material: material
        ))
    }
} 
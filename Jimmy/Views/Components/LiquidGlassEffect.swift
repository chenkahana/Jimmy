import SwiftUI

// MARK: - Liquid Glass Effect Implementation
// Modern glassmorphism effects for iOS 18+ with future iOS 26+ compatibility

/// Custom liquid glass effect view modifier
struct LiquidGlassEffect: ViewModifier {
    let style: LiquidGlassStyle
    let tint: Color?
    let isInteractive: Bool
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Future iOS 26+ native glass effect
            content
                .background(.ultraThinMaterial) // Will use .glassEffect() when iOS 26 is available
        } else {
            // Current iOS 18+ liquid glass implementation
            content
                .background {
                    LiquidGlassBackgroundView(style: style, tint: tint, isInteractive: isInteractive)
                }
        }
    }
}

/// Liquid glass styles
enum LiquidGlassStyle {
    case regular
    case clear
    case thick
    case ultraThin
    
    var material: Material {
        switch self {
        case .regular: return .regularMaterial
        case .clear: return .ultraThinMaterial
        case .thick: return .thickMaterial
        case .ultraThin: return .ultraThinMaterial
        }
    }
    
    var opacity: Double {
        switch self {
        case .regular: return 0.15
        case .clear: return 0.05
        case .thick: return 0.25
        case .ultraThin: return 0.08
        }
    }
}

/// Liquid glass background implementation
private struct LiquidGlassBackgroundView: View {
    let style: LiquidGlassStyle
    let tint: Color?
    let isInteractive: Bool
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // Base material blur
            RoundedRectangle(cornerRadius: 16)
                .fill(style.material)
            
            // Glass overlay with tint
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    (tint ?? Color.white)
                        .opacity(style.opacity * (isPressed && isInteractive ? 1.5 : 1.0))
                )
            
            // Subtle border for glass effect
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .scaleEffect(isPressed && isInteractive ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            if isInteractive {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPressed = false
                    }
                }
            }
        }
    }
}

/// Liquid glass container for grouping elements
struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let style: LiquidGlassStyle
    let content: Content
    
    init(
        spacing: CGFloat = 16,
        style: LiquidGlassStyle = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.style = style
        self.content = content()
    }
    
    var body: some View {
        if #available(iOS 26.0, *) {
            // Future iOS 26+ native GlassEffectContainer
            VStack(spacing: spacing) {
                content
            }
            .background(.ultraThinMaterial) // Will use GlassEffectContainer when available
        } else {
            // Current implementation
            VStack(spacing: spacing) {
                content
            }
            .padding()
            .background {
                LiquidGlassBackgroundView(style: style, tint: nil, isInteractive: false)
            }
        }
    }
}

// MARK: - View Extensions
extension View {
    /// Applies liquid glass effect to the view
    func liquidGlassEffect(
        style: LiquidGlassStyle = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        self.modifier(
            LiquidGlassEffect(
                style: style,
                tint: tint,
                isInteractive: interactive
            )
        )
    }
    
    /// Applies subtle liquid glass effect
    func liquidGlassSubtle() -> some View {
        self.liquidGlassEffect(style: .ultraThin)
    }
    
    /// Applies clear liquid glass effect
    func liquidGlassClear(tint: Color? = nil) -> some View {
        self.liquidGlassEffect(style: .clear, tint: tint)
    }
    
    /// Applies interactive liquid glass effect
    func liquidGlassInteractive(style: LiquidGlassStyle = .regular) -> some View {
        self.liquidGlassEffect(style: style, interactive: true)
    }
}

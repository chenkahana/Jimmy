import SwiftUI

// MARK: - Advanced Liquid Glass Effects
// Implements iOS 26-style liquid glass with depth, motion, and layered materials

/// Advanced liquid glass card with depth and shadows
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let elevation: CGFloat
    
    init(
        cornerRadius: CGFloat = 20,
        shadowRadius: CGFloat = 20,
        elevation: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.elevation = elevation
    }
    
    var body: some View {
        content
            .background(
                ZStack {
                    // Deep shadow for elevation
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black.opacity(0.1))
                        .blur(radius: shadowRadius)
                        .offset(y: elevation)
                    
                    // Main glass surface
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    // Frosted overlay
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Highlight border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

/// Liquid glass navigation bar
struct LiquidGlassNavigationBar<Content: View>: View {
    let content: Content
    let height: CGFloat
    
    init(height: CGFloat = 88, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.height = height
    }
    
    var body: some View {
        content
            .frame(height: height)
            .background(
                ZStack {
                    // Base blur
                    Rectangle()
                        .fill(.regularMaterial)
                    
                    // Gradient overlay for depth
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Bottom separator
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 0.5)
                    }
                }
            )
    }
}

/// Advanced liquid glass tab bar background
struct AdvancedLiquidGlassTabBar<Content: View>: View {
    let content: Content
    let height: CGFloat
    
    init(height: CGFloat = 83, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.height = height
    }
    
    var body: some View {
        content
            .frame(height: height)
            .background(
                ZStack {
                    // Base material
                    Rectangle()
                        .fill(.regularMaterial)
                    
                    // Frosted effect
                    Rectangle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                    
                    // Top highlight
                    VStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 0.5)
                        Spacer()
                    }
                }
            )
    }
}

/// Liquid glass button with haptic feedback
struct LiquidGlassButton<Content: View>: View {
    let content: Content
    let action: () -> Void
    let style: LiquidGlassButtonStyle
    
    @State private var isPressed = false
    
    init(
        style: LiquidGlassButtonStyle = .primary,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.action = action
        self.style = style
    }
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            action()
        }) {
            content
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        // Base shape
                        RoundedRectangle(cornerRadius: 16)
                            .fill(style.material)
                        
                        // Pressed overlay
                        if isPressed {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        }
                        
                        // Tint overlay
                        RoundedRectangle(cornerRadius: 16)
                            .fill(style.tint.opacity(style.tintOpacity))
                        
                        // Border
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(style.borderColor, lineWidth: 0.5)
                    }
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) { isPressing in
            isPressed = isPressing
        } perform: {}
    }
}

/// Liquid glass button styles
enum LiquidGlassButtonStyle {
    case primary
    case secondary
    case destructive
    case clear
    
    var material: Material {
        switch self {
        case .primary: return .regularMaterial
        case .secondary: return .thinMaterial
        case .destructive: return .regularMaterial
        case .clear: return .ultraThinMaterial
        }
    }
    
    var tint: Color {
        switch self {
        case .primary: return .blue
        case .secondary: return .gray
        case .destructive: return .red
        case .clear: return .clear
        }
    }
    
    var tintOpacity: Double {
        switch self {
        case .primary: return 0.15
        case .secondary: return 0.08
        case .destructive: return 0.12
        case .clear: return 0.0
        }
    }
    
    var borderColor: Color {
        switch self {
        case .primary: return Color.blue.opacity(0.3)
        case .secondary: return Color.white.opacity(0.2)
        case .destructive: return Color.red.opacity(0.3)
        case .clear: return Color.white.opacity(0.1)
        }
    }
}

/// Liquid glass modal/sheet background
struct LiquidGlassModal<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                ZStack {
                    // Dimmed background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    // Glass panel
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.thickMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
                }
            )
    }
}

// MARK: - View Extensions for Advanced Effects
extension View {
    /// Wraps content in a liquid glass card
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        shadowRadius: CGFloat = 20,
        elevation: CGFloat = 8
    ) -> some View {
        LiquidGlassCard(
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            elevation: elevation
        ) {
            self
        }
    }
    
    /// Applies liquid glass navigation bar background
    func liquidGlassNavigationBar(height: CGFloat = 88) -> some View {
        LiquidGlassNavigationBar(height: height) {
            self
        }
    }
    
    /// Applies advanced liquid glass tab bar background
    func advancedLiquidGlassTabBar(height: CGFloat = 83) -> some View {
        AdvancedLiquidGlassTabBar(height: height) {
            self
        }
    }
    
    /// Wraps content in a liquid glass modal
    func liquidGlassModal() -> some View {
        LiquidGlassModal {
            self
        }
    }
}

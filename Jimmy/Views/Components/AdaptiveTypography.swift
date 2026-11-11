import SwiftUI

/// 📝 Adaptive Typography System - Apple-grade typography that scales beautifully
/// Implements Apple's latest typography guidelines with perfect spacing and hierarchy
struct AdaptiveTypography {
    
    /// Dynamic type scale that responds to system accessibility settings
    enum Style {
        case largeTitle
        case title1
        case title2
        case title3
        case headline
        case body
        case callout
        case subheadline
        case footnote
        case caption1
        case caption2
        
        var font: Font {
            switch self {
            case .largeTitle:
                return .system(.largeTitle, design: .rounded, weight: .bold)
            case .title1:
                return .system(.title, design: .rounded, weight: .bold)
            case .title2:
                return .system(.title2, design: .rounded, weight: .semibold)
            case .title3:
                return .system(.title3, design: .rounded, weight: .semibold)
            case .headline:
                return .system(.headline, design: .rounded, weight: .semibold)
            case .body:
                return .system(.body, design: .default, weight: .regular)
            case .callout:
                return .system(.callout, design: .default, weight: .medium)
            case .subheadline:
                return .system(.subheadline, design: .default, weight: .regular)
            case .footnote:
                return .system(.footnote, design: .default, weight: .regular)
            case .caption1:
                return .system(.caption, design: .default, weight: .medium)
            case .caption2:
                return .system(.caption2, design: .default, weight: .regular)
            }
        }
        
        var lineHeight: CGFloat {
            switch self {
            case .largeTitle: return 1.2
            case .title1: return 1.25
            case .title2: return 1.3
            case .title3: return 1.35
            case .headline: return 1.4
            case .body: return 1.45
            case .callout: return 1.4
            case .subheadline: return 1.4
            case .footnote: return 1.35
            case .caption1: return 1.3
            case .caption2: return 1.25
            }
        }
        
        var letterSpacing: CGFloat {
            switch self {
            case .largeTitle: return -0.5
            case .title1: return -0.3
            case .title2: return -0.2
            case .title3: return -0.1
            case .headline: return 0
            case .body: return 0
            case .callout: return 0.1
            case .subheadline: return 0.1
            case .footnote: return 0.1
            case .caption1: return 0.2
            case .caption2: return 0.2
            }
        }
        
        var foregroundStyle: AnyShapeStyle {
            switch self {
            case .largeTitle, .title1, .title2, .title3, .headline:
                return AnyShapeStyle(.primary)
            case .body, .callout:
                return AnyShapeStyle(.primary)
            case .subheadline, .footnote, .caption1, .caption2:
                return AnyShapeStyle(.secondary)
            }
        }
    }
}

/// Text view with adaptive typography and beautiful animations
struct AdaptiveText: View {
    let text: String
    let style: AdaptiveTypography.Style
    let alignment: TextAlignment
    let maxLines: Int?
    let animated: Bool
    
    @State private var animationPhase: CGFloat = 0
    @State private var hasAppeared = false
    
    init(
        _ text: String,
        style: AdaptiveTypography.Style,
        alignment: TextAlignment = .leading,
        maxLines: Int? = nil,
        animated: Bool = false
    ) {
        self.text = text
        self.style = style
        self.alignment = alignment
        self.maxLines = maxLines
        self.animated = animated
    }
    
    var body: some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(style.foregroundStyle)
            .kerning(style.letterSpacing)
            .lineSpacing(style.lineHeight)
            .multilineTextAlignment(alignment)
            .lineLimit(maxLines)
            .opacity(hasAppeared ? 1.0 : 0.6)
            .blur(radius: hasAppeared ? 0 : 1)
            .offset(y: hasAppeared ? 0 : 8)
            .onAppear {
                if animated {
                    withAnimation(.motionGentle.delay(0.1)) {
                        hasAppeared = true
                    }
                    startTextAnimation()
                } else {
                    hasAppeared = true
                }
            }
    }
    
    private func startTextAnimation() {
        guard animated else { return }
        
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            animationPhase = 1.0
        }
    }
}

/// Animated text reveal effect
struct TextRevealAnimation: View {
    let text: String
    let style: AdaptiveTypography.Style
    let revealDelay: Double
    
    @State private var revealedCharacters = 0
    
    init(
        _ text: String,
        style: AdaptiveTypography.Style,
        delay: Double = 0.0
    ) {
        self.text = text
        self.style = style
        self.revealDelay = delay
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(style.font)
                    .foregroundStyle(style.foregroundStyle)
                    .opacity(index < revealedCharacters ? 1.0 : 0.3)
                    .blur(radius: index < revealedCharacters ? 0 : 2)
                    .scaleEffect(index < revealedCharacters ? 1.0 : 0.8)
                    .animation(
                        .motionGentle.delay(Double(index) * 0.03 + revealDelay),
                        value: revealedCharacters
                    )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
                withAnimation {
                    revealedCharacters = text.count
                }
            }
        }
    }
}

/// Gradient text with beautiful color transitions
struct GradientText: View {
    let text: String
    let style: AdaptiveTypography.Style
    let gradient: LinearGradient
    
    @State private var animationPhase: CGFloat = 0
    
    init(
        _ text: String,
        style: AdaptiveTypography.Style,
        colors: [Color] = [.accentColor, .purple, .blue]
    ) {
        self.text = text
        self.style = style
        self.gradient = LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Text(text)
            .font(style.font)
            .kerning(style.letterSpacing)
            .lineSpacing(style.lineHeight)
            .foregroundStyle(gradient)
            .overlay {
                // Shimmer effect
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.6),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .mask(
                        Text(text)
                            .font(style.font)
                            .kerning(style.letterSpacing)
                    )
                    .rotationEffect(.degrees(45))
                    .offset(x: animationPhase * 200 - 100)
                    .animation(
                        .linear(duration: 2.0).repeatForever(autoreverses: false),
                        value: animationPhase
                    )
            }
            .onAppear {
                animationPhase = 1.0
            }
    }
}

/// Enhanced spacing system for perfect visual hierarchy
struct AdaptiveSpacing {
    static let micro: CGFloat = 2
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
    static let huge: CGFloat = 32
    static let massive: CGFloat = 48
    
    /// Responsive spacing that adapts to screen size
    static func responsive(_ base: CGFloat) -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let scaleFactor = screenWidth / 375.0 // iPhone base width
        return base * max(0.8, min(1.2, scaleFactor))
    }
}

/// View modifier for perfect spacing
struct AdaptiveSpacingModifier: ViewModifier {
    let spacing: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(AdaptiveSpacing.responsive(spacing))
    }
}

extension View {
    func adaptiveSpacing(_ spacing: CGFloat) -> some View {
        modifier(AdaptiveSpacingModifier(spacing: spacing))
    }
    
    func perfectSpacing() -> some View {
        self.adaptiveSpacing(AdaptiveSpacing.medium)
    }
}

/// Convenience extensions for common text styles
extension View {
    func heroTitle(_ text: String, animated: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: AdaptiveSpacing.small) {
            self
            AdaptiveText(text, style: .largeTitle, animated: animated)
        }
    }
    
    func sectionTitle(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AdaptiveSpacing.tiny) {
            self
            AdaptiveText(text, style: .headline)
        }
    }
    
    func body(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AdaptiveSpacing.small) {
            self
            AdaptiveText(text, style: .body)
        }
    }
    
    func caption(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: AdaptiveSpacing.tiny) {
            self
            AdaptiveText(text, style: .caption1)
        }
    }
}

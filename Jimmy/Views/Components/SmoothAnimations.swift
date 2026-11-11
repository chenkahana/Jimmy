import SwiftUI
import UIKit

// MARK: - Smooth Animation System

/// High-performance animation system optimized for 60fps+ performance
struct SmoothAnimationManager {
    static let shared = SmoothAnimationManager()
    
    private init() {}
    
    // MARK: - Optimized Animation Curves
    
    /// Ultra-smooth spring animation for UI interactions
    static var smoothSpring: Animation {
        .interpolatingSpring(
            mass: 1.0,
            stiffness: 300,
            damping: 30,
            initialVelocity: 0
        )
    }
    
    /// Quick response animation for immediate feedback
    static var quickResponse: Animation {
        .interpolatingSpring(
            mass: 0.8,
            stiffness: 400,
            damping: 25,
            initialVelocity: 0
        )
    }
    
    /// Gentle animation for content transitions
    static var gentleTransition: Animation {
        .interpolatingSpring(
            mass: 1.2,
            stiffness: 200,
            damping: 35,
            initialVelocity: 0
        )
    }
    
    /// Bouncy animation for playful interactions
    static var bouncySpring: Animation {
        .interpolatingSpring(
            mass: 0.6,
            stiffness: 350,
            damping: 20,
            initialVelocity: 5
        )
    }
    
    /// Easing animations optimized for performance
    static var smoothEaseIn: Animation {
        .timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.3)
    }
    
    static var smoothEaseOut: Animation {
        .timingCurve(0.0, 0.0, 0.58, 1.0, duration: 0.3)
    }
    
    static var smoothEaseInOut: Animation {
        .timingCurve(0.42, 0.0, 0.58, 1.0, duration: 0.3)
    }
}

// MARK: - Smooth Transition Components

/// Smooth fade transition with optimized performance
struct SmoothFadeTransition: ViewModifier {
    let isVisible: Bool
    let duration: Double
    
    init(isVisible: Bool, duration: Double = 0.3) {
        self.isVisible = isVisible
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(SmoothAnimationManager.smoothEaseInOut, value: isVisible)
    }
}

/// Smooth scale transition for interactive elements
struct SmoothScaleTransition: ViewModifier {
    let isPressed: Bool
    let scale: CGFloat
    
    init(isPressed: Bool, scale: CGFloat = 0.95) {
        self.isPressed = isPressed
        self.scale = scale
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(SmoothAnimationManager.quickResponse, value: isPressed)
    }
}

/// Smooth slide transition for content changes
struct SmoothSlideTransition: ViewModifier {
    let offset: CGFloat
    let isVisible: Bool
    
    init(offset: CGFloat = 20, isVisible: Bool) {
        self.offset = offset
        self.isVisible = isVisible
    }
    
    func body(content: Content) -> some View {
        content
            .offset(y: isVisible ? 0 : offset)
            .opacity(isVisible ? 1 : 0)
            .animation(SmoothAnimationManager.gentleTransition, value: isVisible)
    }
}

// MARK: - Interactive Animation Components

/// Smooth button with optimized press animations
struct SmoothButton<Content: View>: View {
    let action: () -> Void
    let content: () -> Content
    
    @State private var isPressed = false
    
    init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }
    
    var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(SmoothButtonStyle())
    }
}

struct SmoothButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Smooth toggle with fluid state transitions
struct SmoothToggle: View {
    @Binding var isOn: Bool
    let onColor: Color
    let offColor: Color
    
    init(
        isOn: Binding<Bool>,
        onColor: Color = .blue,
        offColor: Color = Color(.systemGray4)
    ) {
        self._isOn = isOn
        self.onColor = onColor
        self.offColor = offColor
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isOn ? onColor : offColor)
            .frame(width: 50, height: 30)
            .overlay(
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .offset(x: isOn ? 10 : -10)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            )
            .onTapGesture {
                withAnimation(SmoothAnimationManager.smoothSpring) {
                    isOn.toggle()
                }
            }
    }
}

// MARK: - Loading State Animations

/// Smooth loading spinner with optimized performance
struct SmoothLoadingSpinner: View {
    @State private var rotation: Double = 0
    let size: CGFloat
    let lineWidth: CGFloat
    
    init(size: CGFloat = 20, lineWidth: CGFloat = 2) {
        self.size = size
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        Circle()
            .trim(from: 0.2, to: 1.0)
            .stroke(
                AngularGradient(
                    colors: [.clear, .blue],
                    center: .center
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

/// Smooth progress bar with fluid animations
struct SmoothProgressBar: View {
    let progress: Double
    let height: CGFloat
    let backgroundColor: Color
    let foregroundColor: Color
    
    init(
        progress: Double,
        height: CGFloat = 4,
        backgroundColor: Color = Color(.systemGray5),
        foregroundColor: Color = .blue
    ) {
        self.progress = progress
        self.height = height
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(backgroundColor)
                
                // Progress
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: height)
        .animation(SmoothAnimationManager.gentleTransition, value: progress)
    }
}

// MARK: - Content Transition Animations

/// Smooth content switcher with optimized transitions
struct SmoothContentSwitcher<Content: View>: View {
    let content: Content
    let id: AnyHashable
    
    init(id: AnyHashable, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }
    
    var body: some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(id)
            .animation(SmoothAnimationManager.gentleTransition, value: id)
    }
}

/// Smooth list item animations for add/remove operations
struct SmoothListItemTransition: ViewModifier {
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            ))
    }
}

// MARK: - View Extensions for Smooth Animations

extension View {
    /// Apply smooth fade transition
    func smoothFade(isVisible: Bool, duration: Double = 0.3) -> some View {
        modifier(SmoothFadeTransition(isVisible: isVisible, duration: duration))
    }
    
    /// Apply smooth scale transition for press states
    func smoothScale(isPressed: Bool, scale: CGFloat = 0.95) -> some View {
        modifier(SmoothScaleTransition(isPressed: isPressed, scale: scale))
    }
    
    /// Apply smooth slide transition
    func smoothSlide(offset: CGFloat = 20, isVisible: Bool) -> some View {
        modifier(SmoothSlideTransition(offset: offset, isVisible: isVisible))
    }
    
    /// Apply smooth list item transition
    func smoothListTransition() -> some View {
        modifier(SmoothListItemTransition())
    }
    
    /// Apply smooth spring animation to any value change
    func smoothSpring<V: Equatable>(value: V) -> some View {
        animation(SmoothAnimationManager.smoothSpring, value: value)
    }
    
    /// Apply quick response animation for immediate feedback
    func quickResponse<V: Equatable>(value: V) -> some View {
        animation(SmoothAnimationManager.quickResponse, value: value)
    }
    
    /// Apply gentle transition animation for content changes
    func gentleTransition<V: Equatable>(value: V) -> some View {
        animation(SmoothAnimationManager.gentleTransition, value: value)
    }
}

// MARK: - Performance-Optimized Animation Helpers

/// Animation performance optimizer that reduces animations during heavy operations
class AnimationPerformanceOptimizer: ObservableObject {
    static let shared = AnimationPerformanceOptimizer()
    
    @Published var isOptimizing = false
    @Published var reducedMotionEnabled = false
    
    private init() {
        // Check for reduced motion preference
        reducedMotionEnabled = UIAccessibility.isReduceMotionEnabled
        
        // Listen for accessibility changes
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reducedMotionEnabled = UIAccessibility.isReduceMotionEnabled
        }
    }
    
    /// Temporarily reduce animations during heavy operations
    func optimizeForPerformance(duration: TimeInterval = 2.0) {
        isOptimizing = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.isOptimizing = false
        }
    }
    
    /// Get appropriate animation based on current optimization state
    func getOptimizedAnimation(_ defaultAnimation: Animation) -> Animation? {
        if reducedMotionEnabled {
            return nil // No animation for reduced motion
        } else if isOptimizing {
            return .linear(duration: 0.1) // Very fast animation during optimization
        } else {
            return defaultAnimation
        }
    }
}

/// View modifier that respects performance optimization and accessibility
struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    
    @ObservedObject private var optimizer = AnimationPerformanceOptimizer.shared
    
    func body(content: Content) -> some View {
        content
            .animation(optimizer.getOptimizedAnimation(animation), value: value)
    }
}

extension View {
    /// Apply animation that respects performance optimization and accessibility
    func accessibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }
}
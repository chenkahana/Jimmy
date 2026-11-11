import SwiftUI

/// Custom environment key for high contrast mode
private struct HighContrastKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isHighContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
}

/// Applies high-contrast visual adjustments when the setting is enabled.
/// Propagates via environment so child views can read `\.isHighContrast`.
struct HighContrastModifier: ViewModifier {
    @AppStorage("highContrastMode") private var highContrastMode = false

    func body(content: Content) -> some View {
        content
            .environment(\.isHighContrast, highContrastMode)
            .fontWeight(highContrastMode ? .semibold : nil)
    }
}

/// Respects reduced motion — use this instead of withAnimation where needed
struct MotionSafeAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}

extension View {
    /// Apply high-contrast mode if enabled in settings
    func highContrastAware() -> some View {
        modifier(HighContrastModifier())
    }

    /// Disable animations when Reduce Motion is enabled
    func motionSafe() -> some View {
        modifier(MotionSafeAnimation())
    }
}

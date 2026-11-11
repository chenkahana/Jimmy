import SwiftUI

struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double {
        min(Double(index) * 0.04, 0.48)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1.0 : 0.96)
            .offset(y: isVisible ? 0 : 15)
            .onAppear {
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(
                        .spring(response: 0.45, dampingFraction: 0.82)
                        .delay(delay)
                    ) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppearModifier(index: index))
    }
}

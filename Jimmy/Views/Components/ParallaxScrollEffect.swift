import SwiftUI

/// 🌊 Parallax Scroll Effect - Creates stunning depth and immersion
/// This component adds iOS 17+ style parallax effects to any scrollable content
struct ParallaxScrollEffect: View {
    let content: AnyView
    let parallaxRatio: CGFloat
    let id: String
    
    @State private var scrollOffset: CGFloat = 0
    
    init<Content: View>(
        parallaxRatio: CGFloat = 0.3,
        id: String = UUID().uuidString,
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
        self.parallaxRatio = parallaxRatio
        self.id = id
    }
    
    var body: some View {
        GeometryReader { geometry in
            content
                .offset(y: scrollOffset * parallaxRatio)
                .onPreferenceChange(ParallaxScrollOffsetPreferenceKey.self) { value in
                    withAnimation(.motionMicro) {
                        scrollOffset = value
                    }
                }
        }
    }
}

/// Scroll offset tracking for parallax effects
struct ParallaxScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Scroll offset modifier to track scroll position
struct ScrollOffsetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ParallaxScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                }
            )
    }
}

extension View {
    func trackScrollOffset() -> some View {
        modifier(ScrollOffsetModifier())
    }
    
    func parallaxEffect(ratio: CGFloat = 0.3) -> some View {
        ParallaxScrollEffect(parallaxRatio: ratio) {
            self
        }
    }
}

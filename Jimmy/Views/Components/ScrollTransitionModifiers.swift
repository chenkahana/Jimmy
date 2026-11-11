import SwiftUI

extension View {
    @ViewBuilder
    func scrollEdgeTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.7)
                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    .offset(y: phase.isIdentity ? 0 : phase.value * 8)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func carouselScrollTransition() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.8)), axis: .horizontal) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                    .rotation3DEffect(
                        .degrees(phase.value * 5),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
        } else {
            self
        }
    }
}

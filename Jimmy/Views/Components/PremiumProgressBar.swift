import SwiftUI

struct PremiumProgressBar: View {
    let progress: Double
    var height: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: height)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * CGFloat(min(progress, 1.0))), height: height)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.85),
                        value: progress
                    )

                if progress > 0.02 && progress < 0.98 && !reduceMotion {
                    Circle()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(width: height * 2.5, height: height * 2.5)
                        .blur(radius: height * 0.8)
                        .offset(x: max(0, geometry.size.width * CGFloat(min(progress, 1.0)) - height * 1.25))
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.85),
                            value: progress
                        )
                }
            }
        }
        .frame(height: height)
    }
}

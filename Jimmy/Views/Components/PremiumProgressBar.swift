import SwiftUI

struct PremiumProgressBar: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(min(progress, 1.0))))
            }
        }
        .frame(height: height)
    }
}

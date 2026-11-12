import SwiftUI

struct AnimatedWaveformBars: View {
    var barCount: Int = 3
    var color: Color = .accentColor
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animating = false

    var body: some View {
        HStack(spacing: size * 0.1) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.08)
                    .fill(color)
                    .frame(width: size * 0.18, height: animating ? barHeight(for: index) : size * 0.25)
                    .animation(
                        reduceMotion ? .none :
                            .easeInOut(duration: duration(for: index))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            animating = true
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        switch index {
        case 0: return size * 0.7
        case 1: return size * 0.95
        default: return size * 0.55
        }
    }

    private func duration(for index: Int) -> Double {
        switch index {
        case 0: return 0.5
        case 1: return 0.4
        default: return 0.6
        }
    }
}

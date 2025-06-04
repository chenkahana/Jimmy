import SwiftUI

struct AppLoadingView: View {
    @Binding var progress: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.6),
                    Color.accentColor.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(radius: 10)

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 180)

                Text("Updating library…")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
    }
}

#if canImport(SwiftUI) && DEBUG
#Preview {
    AppLoadingView(progress: .constant(0.5))
}
#endif

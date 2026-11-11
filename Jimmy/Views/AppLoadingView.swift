import SwiftUI
import os.log

/// Loading view displayed during app initialization
/// Provides visual feedback while services are being initialized in background
struct AppLoadingView: View {
    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AppLoadingView")
    let progress: Double
    
    var body: some View {
        ZStack {
            // Background with liquid glass effect
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // App icon or logo
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .scaleEffect(1.0 + sin(Date().timeIntervalSince1970 * 2) * 0.1)
                    .animation(.motionGentle.repeatForever(autoreverses: true), value: progress) // spring animation refactored
                
                VStack(spacing: 16) {
                    Text("Jimmy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Initializing...")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Progress bar
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .frame(width: 200)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            logger.debug("AppLoadingView appeared with progress: \(progress)")
        }
        .onChange(of: progress) { oldValue, newValue in
            logger.debug("Progress updated from \(oldValue) to \(newValue)")
        }
    }
}

#Preview {
    AppLoadingView(progress: 0.6)
}

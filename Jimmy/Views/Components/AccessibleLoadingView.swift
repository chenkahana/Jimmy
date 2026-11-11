import SwiftUI

/// Accessible loading view with proper VoiceOver announcements
struct AccessibleLoadingView: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    
    @StateObject private var accessibilityService = AccessibilityService.shared
    @State private var hasAnnouncedLoading = false
    
    init(
        message: String = "Loading",
        showProgress: Bool = false,
        progress: Double? = nil
    ) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Loading indicator
            if showProgress, let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Loading progress")
                    .accessibilityValue("\(Int(progress * 100)) percent complete")
            } else {
                ProgressView()
                    .scaleEffect(1.2)
                    .accessibilityLabel("Loading indicator")
                    .accessibilityHidden(accessibilityService.isVoiceOverEnabled)
            }
            
            // Loading message
            Text(message)
                .font(.system(.body, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            if !hasAnnouncedLoading {
                accessibilityService.announce(message)
                hasAnnouncedLoading = true
            }
        }
        .onChange(of: progress) { _, newProgress in
            if let newProgress = newProgress, showProgress {
                let percent = Int(newProgress * 100)
                if percent % 25 == 0 { // Announce at 25%, 50%, 75%, 100%
                    accessibilityService.announce("\(percent) percent complete")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Please wait.")
    }
}

#Preview {
    VStack(spacing: 40) {
        AccessibleLoadingView(message: "Loading podcasts...")
        
        AccessibleLoadingView(
            message: "Downloading episode...",
            showProgress: true,
            progress: 0.65
        )
    }
}
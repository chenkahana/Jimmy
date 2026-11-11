import SwiftUI

/// Non-intrusive error banner with retry functionality
/// Implements Phase 6 requirement: "Non-intrusive error banner / inline Retry"
struct ErrorBannerView: View {
    let message: String
    let retryAction: (() -> Void)?
    let dismissAction: (() -> Void)?
    
    @State private var isVisible = true
    
    init(
        message: String,
        retryAction: (() -> Void)? = nil,
        dismissAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.retryAction = retryAction
        self.dismissAction = dismissAction
    }
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    // Error icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16, weight: .medium))
                    
                    // Error message
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        // Retry button
                        if let retryAction = retryAction {
                            Button("Retry") {
                                retryAction()
                                withAnimation(.motionTransition) { // spring animation refactored
                                    isVisible = false
                                }
                                Motion.mediumHaptic() // haptic feedback added
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                        }
                        
                        // Dismiss button
                        Button(action: {
                            withAnimation(.motionTransition) { // spring animation refactored
                                isVisible = false
                            }
                            Motion.lightHaptic() // haptic feedback added
                            dismissAction?()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.orange.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }
    }
}

/// Inline error view for embedding within lists or content areas
struct InlineErrorView: View {
    let message: String
    let retryAction: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            if let retryAction = retryAction {
                Button("Retry") {
                    retryAction()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue)
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}

/// Error state manager for ViewModels
@MainActor
class ErrorStateManager: ObservableObject {
    @Published var currentError: ErrorState?
    
    struct ErrorState: Identifiable {
        let id = UUID()
        let message: String
        let retryAction: (() -> Void)?
        let timestamp = Date()
    }
    
    func showError(_ message: String, retryAction: (() -> Void)? = nil) {
        currentError = ErrorState(message: message, retryAction: retryAction)
    }
    
    func clearError() {
        currentError = nil
    }
    
    func retry() {
        currentError?.retryAction?()
        clearError()
    }
}

// MARK: - View Extensions

extension View {
    /// Add error banner overlay to any view
    func errorBanner(
        error: Binding<String?>,
        retryAction: (() -> Void)? = nil
    ) -> some View {
        ZStack(alignment: .top) {
            self
            
            if let errorMessage = error.wrappedValue {
                ErrorBannerView(
                    message: errorMessage,
                    retryAction: retryAction,
                    dismissAction: {
                        error.wrappedValue = nil
                    }
                )
                .zIndex(1000)
            }
        }
    }
    
    /// Add error banner using ErrorStateManager
    func errorBanner(errorManager: ErrorStateManager) -> some View {
        ZStack(alignment: .top) {
            self
            
            if let errorState = errorManager.currentError {
                ErrorBannerView(
                    message: errorState.message,
                    retryAction: errorState.retryAction,
                    dismissAction: {
                        errorManager.clearError()
                    }
                )
                .zIndex(1000)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ErrorBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ErrorBannerView(
                message: "Failed to load episodes. Please check your internet connection.",
                retryAction: {}
            )
            
            InlineErrorView(
                message: "Unable to connect to podcast feed. The server might be temporarily unavailable.",
                retryAction: {}
            )
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
#endif 
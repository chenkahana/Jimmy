import SwiftUI

/// View for displaying subscription-related errors with retry and dismiss actions
struct SubscriptionErrorView: View {
    let error: SubscriptionError
    let podcastTitle: String
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Error icon
            Image(systemName: errorIcon)
                .font(.system(size: 32))
                .foregroundColor(errorColor)
            
            // Error title
            Text(errorTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            // Error message
            Text(error.errorDescription ?? "An unknown error occurred")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Recovery suggestion
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Dismiss button
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                // Retry button (only for retryable errors)
                if isRetryable {
                    Button("Try Again") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Computed Properties
    
    private var errorIcon: String {
        switch error {
        case .networkError:
            return "wifi.exclamationmark"
        case .databaseError:
            return "externaldrive.badge.exclamationmark"
        case .alreadySubscribed:
            return "checkmark.circle.fill"
        case .notSubscribed:
            return "minus.circle"
        case .notFound:
            return "questionmark.circle"
        case .timeout:
            return "clock.badge.exclamationmark"
        case .unknownError:
            return "exclamationmark.triangle"
        }
    }
    
    private var errorColor: Color {
        switch error {
        case .alreadySubscribed:
            return .green
        case .networkError, .timeout:
            return .orange
        case .databaseError, .notFound, .unknownError:
            return .red
        case .notSubscribed:
            return .blue
        }
    }
    
    private var errorTitle: String {
        switch error {
        case .networkError:
            return "Network Error"
        case .databaseError:
            return "Storage Error"
        case .alreadySubscribed:
            return "Already Subscribed"
        case .notSubscribed:
            return "Not Subscribed"
        case .notFound:
            return "Podcast Not Found"
        case .timeout:
            return "Request Timed Out"
        case .unknownError:
            return "Something Went Wrong"
        }
    }
    
    private var isRetryable: Bool {
        switch error {
        case .networkError, .databaseError, .timeout, .unknownError, .notFound:
            return true
        case .alreadySubscribed, .notSubscribed:
            return false
        }
    }
}

// MARK: - Subscription Error Alert Modifier

extension View {
    /// Presents a subscription error alert with retry functionality
    func subscriptionErrorAlert(
        error: Binding<SubscriptionError?>,
        podcastTitle: String,
        onRetry: @escaping () -> Void
    ) -> some View {
        self.alert(
            "Subscription Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            // Dismiss button
            Button("OK", role: .cancel) {
                error.wrappedValue = nil
            }
            
            // Retry button (only for retryable errors)
            if let currentError = error.wrappedValue, isRetryableError(currentError) {
                Button("Try Again") {
                    error.wrappedValue = nil
                    onRetry()
                }
            }
        } message: {
            if let currentError = error.wrappedValue {
                Text(SubscriptionErrorHandler.handle(currentError, for: podcastTitle))
            }
        }
    }
    
    /// Presents a subscription error sheet with detailed information
    func subscriptionErrorSheet(
        error: Binding<SubscriptionError?>,
        podcastTitle: String,
        onRetry: @escaping () -> Void
    ) -> some View {
        self.sheet(
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            if let currentError = error.wrappedValue {
                SubscriptionErrorView(
                    error: currentError,
                    podcastTitle: podcastTitle,
                    onRetry: {
                        error.wrappedValue = nil
                        onRetry()
                    },
                    onDismiss: {
                        error.wrappedValue = nil
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Helper Functions

private func isRetryableError(_ error: SubscriptionError) -> Bool {
    switch error {
    case .networkError, .databaseError, .timeout, .unknownError, .notFound:
        return true
    case .alreadySubscribed, .notSubscribed:
        return false
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SubscriptionErrorView(
            error: .networkError("Connection failed"),
            podcastTitle: "Sample Podcast",
            onRetry: {},
            onDismiss: {}
        )
        
        SubscriptionErrorView(
            error: .alreadySubscribed,
            podcastTitle: "Sample Podcast",
            onRetry: {},
            onDismiss: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
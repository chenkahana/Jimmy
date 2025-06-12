import SwiftUI

// MARK: - SwiftUI View Modifier for Loading States

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?
    let style: LoadingStyle
    
    enum LoadingStyle {
        case overlay
        case inline
        case button
    }
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .opacity(isLoading && style == .overlay ? 0.6 : 1.0)
            
            if isLoading {
                switch style {
                case .overlay:
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                LoadingIndicator(size: 30, color: .white)
                                if let message = message {
                                    Text(message)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding()
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .transition(.opacity.combined(with: .scale))
                        
                case .inline:
                    HStack(spacing: 8) {
                        LoadingIndicator(size: 16)
                        if let message = message {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .scale))
                    
                case .button:
                    HStack(spacing: 8) {
                        LoadingIndicator(size: 16, color: .white)
                        Text(message ?? "Loading...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil, style: LoadingOverlay.LoadingStyle = .overlay) -> some View {
        self.modifier(LoadingOverlay(isLoading: isLoading, message: message, style: style))
    }
    
    func loadingState(_ key: String, manager: LoadingStateManager = .shared) -> some View {
        self.loadingOverlay(
            isLoading: manager.isLoading(key),
            message: manager.loadingMessage(key)
        )
    }
} 
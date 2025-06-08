import Foundation
import SwiftUI

class LoadingStateManager: ObservableObject {
    static let shared = LoadingStateManager()
    
    @Published private var loadingStates: [String: Bool] = [:]
    @Published private var loadingMessages: [String: String] = [:]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func setLoading(_ key: String, isLoading: Bool, message: String? = nil) {
        Task { @MainActor in
            self.loadingStates[key] = isLoading
            if let message = message {
                self.loadingMessages[key] = message
            } else {
                self.loadingMessages.removeValue(forKey: key)
            }
            
            // Clean up if not loading
            if !isLoading {
                self.loadingStates.removeValue(forKey: key)
                self.loadingMessages.removeValue(forKey: key)
            }
        }
    }
    
    func isLoading(_ key: String) -> Bool {
        return loadingStates[key] ?? false
    }
    
    func loadingMessage(_ key: String) -> String? {
        return loadingMessages[key]
    }
    
    func clearAllLoading() {
        Task { @MainActor in
            self.loadingStates.removeAll()
            self.loadingMessages.removeAll()
        }
    }
    
    // MARK: - Convenience Methods for Common Operations
    
    func setEpisodeLoading(_ episodeID: UUID, isLoading: Bool) {
        setLoading("episode_\(episodeID)", isLoading: isLoading, message: isLoading ? "Loading episode..." : nil)
    }
    
    func isEpisodeLoading(_ episodeID: UUID) -> Bool {
        return isLoading("episode_\(episodeID)")
    }
    
    func setPodcastLoading(_ podcastID: UUID, isLoading: Bool) {
        setLoading("podcast_\(podcastID)", isLoading: isLoading, message: isLoading ? "Loading podcast..." : nil)
    }
    
    func isPodcastLoading(_ podcastID: UUID) -> Bool {
        return isLoading("podcast_\(podcastID)")
    }
    
    func setSearchLoading(isLoading: Bool) {
        setLoading("search", isLoading: isLoading, message: isLoading ? "Searching..." : nil)
    }
    
    func isSearchLoading() -> Bool {
        return isLoading("search")
    }
    
    func setImportLoading(isLoading: Bool) {
        setLoading("import", isLoading: isLoading, message: isLoading ? "Importing..." : nil)
    }
    
    func isImportLoading() -> Bool {
        return isLoading("import")
    }
}

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
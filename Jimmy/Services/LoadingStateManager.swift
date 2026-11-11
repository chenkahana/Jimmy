import Foundation
import Combine
import SwiftUI

@MainActor
class LoadingStateManager: ObservableObject {
    static let shared = LoadingStateManager()
    
    @Published private var loadingStates: [String: LoadingState] = [:]
    
    private init() {}
    
    // MARK: - Loading State Definition
    
    enum LoadingState: Equatable {
        case idle
        case loading(message: String? = nil)
        case loaded
        case error(message: String, canRetry: Bool = true)
        
        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
        
        var isError: Bool {
            if case .error = self { return true }
            return false
        }
        
        var message: String? {
            switch self {
            case .loading(let message):
                return message
            case .error(let message, _):
                return message
            default:
                return nil
            }
        }
        
        var canRetry: Bool {
            if case .error(_, let canRetry) = self {
                return canRetry
            }
            return false
        }
    }
    
    // MARK: - Public Interface
    
    func setState(_ key: String, state: LoadingState) {
        loadingStates[key] = state
        
        // PERFORMANCE FIX: Faster cleanup for better responsiveness
        if state == .idle || state == .loaded {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds (faster cleanup)
                if loadingStates[key] == state {
                    loadingStates.removeValue(forKey: key)
                }
            }
        }
    }
    
    func getState(_ key: String) -> LoadingState {
        return loadingStates[key] ?? .idle
    }
    
    func setLoading(_ key: String, message: String? = nil) {
        setState(key, state: .loading(message: message))
    }
    
    func setLoaded(_ key: String) {
        setState(key, state: .loaded)
    }
    
    func setError(_ key: String, message: String, canRetry: Bool = true) {
        setState(key, state: .error(message: message, canRetry: canRetry))
    }
    
    func setIdle(_ key: String) {
        setState(key, state: .idle)
    }
    
    func isLoading(_ key: String) -> Bool {
        return getState(key).isLoading
    }
    
    func isError(_ key: String) -> Bool {
        return getState(key).isError
    }
    
    func clearAllStates() {
        loadingStates.removeAll()
    }
    
    // MARK: - Convenience Methods for Common Operations
    
    func setEpisodeLoading(_ episodeID: UUID) {
        setLoading("episode_\(episodeID)", message: "Loading episode...")
    }
    
    func setEpisodeLoaded(_ episodeID: UUID) {
        setLoaded("episode_\(episodeID)")
    }
    
    func setEpisodeError(_ episodeID: UUID, message: String) {
        setError("episode_\(episodeID)", message: message)
    }
    
    func isEpisodeLoading(_ episodeID: UUID) -> Bool {
        return isLoading("episode_\(episodeID)")
    }
    
    func getEpisodeState(_ episodeID: UUID) -> LoadingState {
        return getState("episode_\(episodeID)")
    }
    
    func setPodcastLoading(_ podcastID: UUID) {
        setLoading("podcast_\(podcastID)", message: "Loading podcast...")
    }
    
    func setPodcastLoaded(_ podcastID: UUID) {
        setLoaded("podcast_\(podcastID)")
    }
    
    func setPodcastError(_ podcastID: UUID, message: String) {
        setError("podcast_\(podcastID)", message: message)
    }
    
    func isPodcastLoading(_ podcastID: UUID) -> Bool {
        return isLoading("podcast_\(podcastID)")
    }
    
    func getPodcastState(_ podcastID: UUID) -> LoadingState {
        return getState("podcast_\(podcastID)")
    }
    
    func setSearchLoading() {
        setLoading("search", message: "Searching...")
    }
    
    func setSearchLoaded() {
        setLoaded("search")
    }
    
    func setSearchError(_ message: String) {
        setError("search", message: message)
    }
    
    func isSearchLoading() -> Bool {
        return isLoading("search")
    }
    
    func getSearchState() -> LoadingState {
        return getState("search")
    }
    
    func setDiscoverLoading() {
        setLoading("discover", message: "Loading recommendations...")
    }
    
    func setDiscoverLoaded() {
        setLoaded("discover")
    }
    
    func setDiscoverError(_ message: String) {
        setError("discover", message: message)
    }
    
    func isDiscoverLoading() -> Bool {
        return isLoading("discover")
    }
    
    func getDiscoverState() -> LoadingState {
        return getState("discover")
    }
    
    func setLibraryLoading() {
        setLoading("library", message: "Loading library...")
    }
    
    func setLibraryLoaded() {
        setLoaded("library")
    }
    
    func setLibraryError(_ message: String) {
        setError("library", message: message)
    }
    
    func isLibraryLoading() -> Bool {
        return isLoading("library")
    }
    
    func getLibraryState() -> LoadingState {
        return getState("library")
    }
}

// MARK: - SwiftUI Integration

extension View {
    /// Apply loading state with skeleton view integration
    func loadingState(
        _ key: String,
        skeleton: LiquidSkeletonView.SkeletonStyle,
        skeletonCount: Int = 1,
        manager: LoadingStateManager = .shared
    ) -> some View {
        LoadingStateView(
            key: key,
            skeleton: skeleton,
            skeletonCount: skeletonCount,
            manager: manager
        ) {
            self
        }
    }
}

struct LoadingStateView<Content: View>: View {
    let key: String
    let skeleton: LiquidSkeletonView.SkeletonStyle
    let skeletonCount: Int
    let manager: LoadingStateManager
    @ViewBuilder let content: () -> Content
    
    @State private var showRetryButton = false
    
    var body: some View {
        let state = manager.getState(key)
        
        Group {
            switch state {
            case .idle, .loaded:
                content()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
                
            case .loading(let message):
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        ForEach(0..<skeletonCount, id: \.self) { index in
                            LiquidSkeletonView(style: skeleton)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                    removal: .opacity
                                ))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.05),
                                    value: state.isLoading
                                )
                        }
                    }
                    
                    if let message = message {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .transition(.opacity)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
                
            case .error(let message, let canRetry):
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    if canRetry {
                        Button("Retry") {
                            manager.setLoading(key, message: "Retrying...")
                            // The retry action should be handled by the parent view
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: state)
    }
} 
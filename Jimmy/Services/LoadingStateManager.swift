import Foundation
import Combine

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

// MARK: - Loading State Data
// UI components moved to Views/Components/LoadingOverlay.swift 
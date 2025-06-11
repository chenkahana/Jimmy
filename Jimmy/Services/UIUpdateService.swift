import Foundation
import SwiftUI
import Combine
import OSLog

/// Centralized service for event-driven UI updates with thread-safe coordination
@MainActor
final class UIUpdateService: ObservableObject {
    static let shared = UIUpdateService()
    
    private let logger = Logger(subsystem: "com.jimmy.app", category: "ui-update-service")
    
    // MARK: - Published State
    @Published private(set) var activeOperations: Set<String> = []
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var updateProgress: [String: Double] = [:]
    
    // MARK: - Event Handling
    private var updateHandlers: [String: (Any) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        logger.info("UIUpdateService initialized")
    }
    
    // MARK: - Operation Management
    
    /// Start tracking an operation
    func startOperation(_ operationId: String) {
        activeOperations.insert(operationId)
        isUpdating = !activeOperations.isEmpty
        updateProgress[operationId] = 0.0
        
        logger.debug("Started operation: \(operationId)")
    }
    
    /// Complete an operation
    func completeOperation(_ operationId: String) {
        activeOperations.remove(operationId)
        updateProgress.removeValue(forKey: operationId)
        isUpdating = !activeOperations.isEmpty
        
        logger.debug("Completed operation: \(operationId)")
    }
    
    /// Update operation progress
    func updateProgress(for operationId: String, progress: Double) {
        updateProgress[operationId] = progress
        logger.debug("Updated progress for \(operationId): \(progress)")
    }
    
    // MARK: - Update Handler Registration
    
    /// Register a handler for specific update types
    func registerUpdateHandler<T>(for key: String, handler: @escaping (T) -> Void) {
        updateHandlers[key] = { data in
            if let typedData = data as? T {
                handler(typedData)
            }
        }
        logger.debug("Registered update handler for: \(key)")
    }
    
    /// Unregister a handler
    func unregisterUpdateHandler(for key: String) {
        updateHandlers.removeValue(forKey: key)
        logger.debug("Unregistered update handler for: \(key)")
    }
    
    /// Trigger a specific update handler
    func triggerUpdate<T>(for key: String, with data: T) {
        if let handler = updateHandlers[key] {
            handler(data)
            logger.debug("Triggered update for: \(key)")
        }
    }
    
    // MARK: - Episode-Specific Updates
    
    /// Handle progressive episode updates
    func handleProgressiveEpisodeUpdate(podcastId: UUID, episode: Episode) {
        let key = "episodes-\(podcastId)"
        triggerUpdate(for: key, with: episode)
        
        // Broadcast notification for other components
        NotificationCenter.default.post(
            name: .episodeAdded,
            object: nil,
            userInfo: ["podcastId": podcastId, "episode": episode]
        )
        
        logger.debug("Handled progressive episode update for podcast: \(podcastId)")
    }
    
    /// Handle episode metadata updates
    func handleEpisodeMetadataUpdate(podcastId: UUID, metadata: PodcastMetadata) {
        let key = "metadata-\(podcastId)"
        triggerUpdate(for: key, with: metadata)
        
        // Broadcast notification
        NotificationCenter.default.post(
            name: .podcastMetadataUpdated,
            object: nil,
            userInfo: ["podcastId": podcastId, "metadata": metadata]
        )
        
        logger.debug("Handled metadata update for podcast: \(podcastId)")
    }
    
    /// Handle episode list completion
    func handleEpisodeListCompleted(podcastId: UUID, episodes: [Episode]) {
        let key = "completed-\(podcastId)"
        triggerUpdate(for: key, with: episodes)
        
        // Broadcast notification
        NotificationCenter.default.post(
            name: .episodeListCompleted,
            object: nil,
            userInfo: ["podcastId": podcastId, "episodes": episodes]
        )
        
        logger.debug("Handled episode list completion for podcast: \(podcastId) with \(episodes.count) episodes")
    }
    
    // MARK: - Batch Operations
    
    /// Handle batch update completion
    func handleBatchUpdateCompleted(operationId: String, results: [String: Any]) {
        completeOperation(operationId)
        
        // Broadcast notification
        NotificationCenter.default.post(
            name: .batchUpdateCompleted,
            object: nil,
            userInfo: ["operationId": operationId, "results": results]
        )
        
        logger.info("Batch update completed: \(operationId)")
    }
    
    // MARK: - Cleanup
    
    /// Clean up resources
    func cleanup() {
        updateHandlers.removeAll()
        activeOperations.removeAll()
        updateProgress.removeAll()
        isUpdating = false
        cancellables.removeAll()
        
        logger.info("UIUpdateService cleaned up")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let episodeAdded = Notification.Name("episodeAdded")
    static let podcastMetadataUpdated = Notification.Name("podcastMetadataUpdated")
    static let episodeListCompleted = Notification.Name("episodeListCompleted")
    static let batchUpdateCompleted = Notification.Name("batchUpdateCompleted")
} 
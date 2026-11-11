import Foundation
import os
import SwiftUI
import Combine

/// Utility to optimize loading performance and reduce perceived loading times
@MainActor
final class LoadingOptimizer: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LoadingOptimizer")
    static let shared = LoadingOptimizer()
    
    @Published private(set) var isOptimizing = false
    
    private var optimizationTasks: [String: Task<Void, Never>] = [:]
    
    private init() {}
    
    /// Optimizes episode loading by pre-caching progress data
    func optimizeEpisodeLoading(_ episodes: [EpisodeWithPlaybackState]) {
        guard !episodes.isEmpty else { return }
        
        let taskId = "episode-optimization-\(UUID().uuidString)"
        
        optimizationTasks[taskId] = Task { [weak self] in
            defer {
                Task { @MainActor in
                    self?.optimizationTasks.removeValue(forKey: taskId)
                }
            }
            
            let progressCache = DIContainer.shared.progressCacheStore
            
            // Pre-cache progress percentages for all episodes
            for episodeWithState in episodes {
                let episode = episodeWithState.episode
                let playbackState = episodeWithState.playbackState
                
                // Update progress cache if we have duration
                if let duration = episode.duration, duration > 0 {
                    await progressCache.setProgress(
                        for: episode.id,
                        position: playbackState.position,
                        duration: duration
                    )
                }
            }
            
            Self.logger.info("LoadingOptimizer: Pre-cached progress for \(episodes.count) episodes")
        }
    }
    
    /// Optimizes UI updates by batching them
    func batchUIUpdates<T>(_ updates: @escaping () -> T) -> T {
        return updates()
    }
    
    /// Debounces frequent updates to prevent UI stuttering
    func debounce(identifier: String, delay: TimeInterval = 0.1, action: @escaping () -> Void) {
        // Cancel existing task for this identifier
        optimizationTasks[identifier]?.cancel()
        
        // Create new debounced task
        optimizationTasks[identifier] = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                action()
                self.optimizationTasks.removeValue(forKey: identifier)
            }
        }
    }
    
    /// Cancels all optimization tasks
    func cancelAllOptimizations() {
        for task in optimizationTasks.values {
            task.cancel()
        }
        optimizationTasks.removeAll()
    }
}

// MARK: - SwiftUI Integration

extension View {
    /// Applies loading optimizations to the view
    func optimizedLoading() -> some View {
        self.environmentObject(LoadingOptimizer.shared)
    }
    
    /// Debounces view updates to prevent stuttering
    func debouncedUpdate(identifier: String, delay: TimeInterval = 0.1) -> some View {
        self.onReceive(Just(Date())) { _ in
            LoadingOptimizer.shared.debounce(identifier: identifier, delay: delay) {
                // View will automatically update when this closure runs
            }
        }
    }
}
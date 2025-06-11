import Foundation
import SwiftUI
import Combine
import OSLog

/// ViewModel following CHAT_HELP.md specification
/// Exposes AsyncPublisher<EpisodeChanges> to UI for instant diffs
@MainActor
final class PodcastViewModel: ObservableObject {
    static let shared = PodcastViewModel()
    
    // MARK: - Published Properties
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdateTime: Date?
    
    // MARK: - Private Properties
    private let repository = PodcastRepository.shared
    private let fetchWorker = FetchWorker.shared
    private let podcastStore = PodcastStore.shared
    private var cancellables = Set<AnyCancellable>()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "Jimmy", category: "PodcastViewModel")
    #endif
    
    // MARK: - AsyncPublisher for Changes
    
    /// Expose AsyncPublisher<EpisodeChanges> to UI for instant diffs
    var changesPublisher: AnyPublisher<EpisodeChanges, Never> {
        repository.changesPublisher
    }
    
    /// AsyncSequence for SwiftUI integration
    var changesStream: AsyncPublisher<AnyPublisher<EpisodeChanges, Never>> {
        changesPublisher.values
    }
    
    // MARK: - Initialization
    
    private init() {
        setupChangeSubscription()
        loadInitialData()
    }
    
    /// Setup subscription to repository changes
    private func setupChangeSubscription() {
        repository.changesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changes in
                self?.handleEpisodeChanges(changes)
            }
            .store(in: &cancellables)
    }
    
    /// Load initial data on startup
    private func loadInitialData() {
        Task {
            await loadEpisodes()
        }
    }
    
    // MARK: - Public Interface
    
    /// Load episodes with ≤ 200ms cached response goal
    func loadEpisodes() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        #if canImport(OSLog)
        logger.info("📱 Loading episodes (target: ≤200ms for cached)")
        #endif
        
        let startTime = Date()
        
        do {
            // Fast cached read first (≤ 200ms goal)
            let cachedEpisodes = await podcastStore.readAll()
            
            let cacheTime = Date().timeIntervalSince(startTime)
            
            #if canImport(OSLog)
            logger.info("💾 Loaded \(cachedEpisodes.count) cached episodes in \(String(format: "%.1f", cacheTime * 1000))ms")
            #endif
            
            // Update UI immediately with cached data
            episodes = cachedEpisodes.sorted { 
                let date1 = $0.publishedDate ?? Date.distantPast
                let date2 = $1.publishedDate ?? Date.distantPast
                return date1 > date2
            }
            lastUpdateTime = Date()
            
        } catch {
            #if canImport(OSLog)
            logger.error("❌ Failed to load episodes: \(error.localizedDescription)")
            #endif
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Refresh episodes in background
    func refreshEpisodes(for podcasts: [Podcast]) async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        #if canImport(OSLog)
        logger.info("🔄 Starting background refresh for \(podcasts.count) podcasts")
        #endif
        
        // Batch fetch with ≥ 1,000 episodes/sec goal
        let startTime = Date()
        let episodesByPodcast = await fetchWorker.batchFetchEpisodes(for: podcasts)
        let fetchTime = Date().timeIntervalSince(startTime)
        
        // Calculate throughput
        let totalEpisodes = episodesByPodcast.values.reduce(0) { $0 + $1.count }
        let throughput = Double(totalEpisodes) / fetchTime
        
        #if canImport(OSLog)
        logger.info("📊 Fetch throughput: \(String(format: "%.0f", throughput)) episodes/sec (target: ≥1,000)")
        #endif
        
        // Batch write to store
        await podcastStore.batchWrite(episodesByPodcast)
        
        // Reload episodes to reflect changes
        await loadEpisodes()
        
        isLoading = false
    }
    
    /// Get current snapshot for UI diffable data source
    func currentSnapshot() async -> [Episode] {
        return await podcastStore.readAll()
    }
    
    /// Handle episode changes for instant UI updates
    private func handleEpisodeChanges(_ changes: EpisodeChanges) {
        #if canImport(OSLog)
        logger.debug("🔄 Handling episode changes: \(changes.inserted.count) inserted, \(changes.updated.count) updated, \(changes.deleted.count) deleted")
        #endif
        
        // Apply changes to local episodes array for instant UI updates
        var updatedEpisodes = episodes
        
        // Remove deleted episodes
        updatedEpisodes.removeAll { episode in
            changes.deleted.contains(episode.id)
        }
        
        // Update existing episodes
        for updatedEpisode in changes.updated {
            if let index = updatedEpisodes.firstIndex(where: { $0.id == updatedEpisode.id }) {
                updatedEpisodes[index] = updatedEpisode
            }
        }
        
        // Add new episodes
        updatedEpisodes.append(contentsOf: changes.inserted)
        
        // Sort by published date (newest first)
        updatedEpisodes.sort { 
            let date1 = $0.publishedDate ?? Date.distantPast
            let date2 = $1.publishedDate ?? Date.distantPast
            return date1 > date2
        }
        
        // Update UI (already on main thread due to @MainActor)
        episodes = updatedEpisodes
        lastUpdateTime = Date()
        
        #if canImport(OSLog)
        logger.debug("✅ UI updated with \(updatedEpisodes.count) episodes")
        #endif
    }
    
    // MARK: - Performance Metrics
    
    /// Get performance metrics for monitoring
    func getPerformanceMetrics() async -> PerformanceMetrics {
        return PerformanceMonitor.shared.getCurrentMetrics()
    }
    
    private func calculateCacheHitRate() -> Double {
        // Simplified cache hit rate calculation
        // In a real implementation, you'd track cache hits vs misses
        return 0.85 // 85% cache hit rate example
    }
} 
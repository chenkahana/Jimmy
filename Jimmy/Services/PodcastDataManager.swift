import Foundation
import SwiftUI

/// Simplified podcast data manager with optimized caching and prefetching
class PodcastDataManager: ObservableObject {
    static let shared = PodcastDataManager()
    
    // MARK: - Published Properties
    
    @Published var podcasts: [Podcast] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // MARK: - Services
    
    private let podcastService = PodcastService.shared
    private let episodeCacheService = EpisodeCacheService.shared
    private let imageCache = ImageCache.shared
    
    // MARK: - Cache Management
    
    private let dataQueue = DispatchQueue(label: "podcast-data-manager", qos: .userInitiated)
    private var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 30 * 60 // 30 minutes
    
    // MARK: - Initialization
    
    private init() {
        loadPodcasts()
        setupAutoRefresh()
    }
    
    // MARK: - Public Interface
    
    /// Load podcasts with automatic image prefetching
    func loadPodcasts() {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            let loadedPodcasts = self.podcastService.loadPodcasts()
            
            DispatchQueue.main.async {
                self.podcasts = loadedPodcasts
                
                // Prefetch artwork for visible podcasts
                self.prefetchArtwork(for: loadedPodcasts)
            }
        }
    }
    
    /// Refresh podcast data with intelligent caching
    func refreshPodcasts(force: Bool = false) {
        guard !isLoading else { return }
        
        // Check if refresh is needed
        if !force, let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshInterval {
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            let currentPodcasts = self.podcastService.loadPodcasts()
            
            // Update metadata for all podcasts
            self.refreshPodcastMetadata(podcasts: currentPodcasts) { [weak self] updatedPodcasts, errors in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.lastRefreshTime = Date()
                    
                    if !updatedPodcasts.isEmpty {
                        self?.podcasts = updatedPodcasts
                        self?.prefetchArtwork(for: updatedPodcasts)
                    }
                    
                    if !errors.isEmpty {
                        self?.error = "Some podcasts couldn't be updated: \(errors.joined(separator: ", "))"
                    }
                }
            }
        }
    }
    
    /// Get episodes for a podcast with prefetching
    func getEpisodes(for podcast: Podcast, completion: @escaping ([Episode]) -> Void) {
        episodeCacheService.getEpisodes(for: podcast) { [weak self] episodes in
            completion(episodes)
            
            // Prefetch episode artwork in background
            self?.prefetchEpisodeArtwork(episodes: episodes, podcast: podcast)
        }
    }
    
    /// Remove a podcast and clear its caches
    func removePodcast(_ podcast: Podcast) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Remove from storage
            var allPodcasts = self.podcastService.loadPodcasts()
            allPodcasts.removeAll { $0.id == podcast.id }
            self.podcastService.savePodcasts(allPodcasts)
            
            // Clear caches
            self.episodeCacheService.clearCache(for: podcast.id)
            
            DispatchQueue.main.async {
                self.podcasts.removeAll { $0.id == podcast.id }
            }
        }
    }
    
    /// Get cache statistics
    func getCacheInfo() -> (episodes: String, images: String) {
        let episodeStats = episodeCacheService.getCacheStats()
        let imageStats = imageCache.getCacheStats()
        
        let episodeInfo = "Episodes: \(episodeStats.totalPodcasts) podcasts cached, \(String(format: "%.1f", episodeStats.totalSizeKB / 1024))MB"
        let imageInfo = "Images: \(imageStats.memoryCount) in memory, \(String(format: "%.1f", imageStats.diskSizeMB))MB on disk"
        
        return (episodeInfo, imageInfo)
    }
    
    /// Clear all caches
    func clearAllCaches() {
        episodeCacheService.clearAllCache()
        imageCache.clearAllCaches()
    }
    
    // MARK: - Private Methods
    
    private func prefetchArtwork(for podcasts: [Podcast]) {
        ImagePreloader.preloadPodcastArtwork(podcasts)
    }
    
    private func prefetchEpisodeArtwork(episodes: [Episode], podcast: Podcast) {
        ImagePreloader.preloadEpisodeArtwork(episodes, fallbackPodcast: podcast)
    }
    
    private func refreshPodcastMetadata(
        podcasts: [Podcast],
        completion: @escaping ([Podcast], [String]) -> Void
    ) {
        let group = DispatchGroup()
        var updatedPodcasts: [Podcast] = []
        var errors: [String] = []
        let lock = NSLock()
        
        for podcast in podcasts {
            group.enter()
            
            podcastService.refreshPodcastMetadata(for: podcast) { success in
                defer { group.leave() }
                
                if success {
                    lock.lock()
                    updatedPodcasts.append(podcast)
                    lock.unlock()
                } else {
                    lock.lock()
                    errors.append(podcast.title)
                    lock.unlock()
                }
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            // Load fresh podcast data after updates
            let freshPodcasts = self.podcastService.loadPodcasts()
            completion(freshPodcasts, errors)
        }
    }
    
    private func setupAutoRefresh() {
        // Setup timer for periodic refresh
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshPodcasts()
        }
    }
} 
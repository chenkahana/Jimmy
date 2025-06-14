import Foundation
import SwiftUI

class EpisodeUpdateService {
    static let shared = EpisodeUpdateService()
    
    private(set) var isUpdating = false
    private(set) var lastUpdateTime: Date?
    private(set) var updateProgress: Double = 0.0
    
    private let updateQueue = DispatchQueue(label: "episode-update-queue", qos: .background, attributes: .concurrent)
    private let sortingQueue = DispatchQueue(label: "episode-sorting-queue", qos: .userInitiated)
    private var updateTimer: Timer?
    
    // RSS feeds don't "push" updates - we need to poll them periodically
    // Most podcast apps check every 15-30 minutes for new episodes
    // RSS is a pull-based protocol, not push-based like modern APIs
    // PERFORMANCE FIX: Increased from 30 minutes to 60 minutes to reduce CPU usage
    private let updateInterval: TimeInterval = 3600 // 60 minutes to reduce background load
    
    private init() {
        // REMOVED: Don't start periodic updates automatically to avoid blocking app launch  
        // startPeriodicUpdates() - This will be called manually from JimmyApp.onAppear
        setupAppStateObservers()
    }
    
    deinit {
        stopPeriodicUpdates()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App State Management
    
    private func setupAppStateObservers() {
        // Stop updates when app goes to background to prevent Signal 9 crashes
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPeriodicUpdates()
        }
        
        // Resume updates when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startPeriodicUpdates()
        }
    }
    
    // MARK: - Public Interface
    
    /// Start periodic background updates
    func startPeriodicUpdates() {
        // Prevent starting multiple timers if called again
        guard updateTimer == nil else { return }

        // DISABLED: Don't schedule immediate update on app launch for clean user experience
        // Task {
        //     await updateAllEpisodes()
        // }
        
        // Schedule recurring updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // PERFORMANCE FIX: Only update if app is active to prevent background crashes and reduce CPU usage
            guard UIApplication.shared.applicationState == .active else {
                print("⏸️ Skipping episode update - app not active")
                return
            }
            
            // Additional check: Don't update if already updating
            guard !self.isUpdating else {
                print("⏸️ Skipping episode update - already in progress")
                return
            }
            
            Task {
                await self.updateAllEpisodes()
            }
        }
    }
    
    /// Stop periodic updates
    func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// Manually trigger an update
    func forceUpdate() {
        // WORLD-CLASS NAVIGATION: Prevent background updates from interfering with navigation
        Task {
            // Only add delay if we already have episodes (to prevent interference with navigation)
            // If no episodes exist, update immediately for first-time users
            let episodeCount = EpisodeViewModel.shared.episodes.count
            if episodeCount > 0 {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            }
            await updateAllEpisodes()
        }
    }
    
    // MARK: - Background Update Logic
    
    private func updateAllEpisodes() async {
        // Simple property updates - no SwiftUI publishing needed
        guard !isUpdating else { return }
        isUpdating = true
        updateProgress = 0.0
        
        let podcasts = PodcastService.shared.loadPodcasts()
        guard !podcasts.isEmpty else {
            isUpdating = false
            return
        }
        
        print("🔄 Starting background episode update for \(podcasts.count) podcasts")
        
        // Limit concurrent operations to prevent memory pressure
        let maxConcurrentOperations = min(podcasts.count, 3) // Max 3 concurrent operations
        let batches = podcasts.chunked(into: maxConcurrentOperations)
        
        var allNewEpisodes: [Episode] = []
        var episodesByPodcast: [UUID: [Episode]] = [:]
        var updatedPodcasts: [Podcast] = []
        let totalPodcasts = Double(podcasts.count)
        
        // Process podcasts in batches to control memory usage
        var completedCount = 0
        for batch in batches {
            await withTaskGroup(of: (Podcast, [Episode]).self) { group in
                for podcast in batch {
                    group.addTask {
                        await self.fetchEpisodesForPodcast(podcast)
                    }
                }
                
                for await (podcast, episodes) in group {
                    completedCount += 1
                    let currentProgress = Double(completedCount) / totalPodcasts
                    self.updateProgress = currentProgress
                    
                    if !episodes.isEmpty {
                        allNewEpisodes.append(contentsOf: episodes)
                        episodesByPodcast[podcast.id] = episodes
                        
                        // Update podcast's lastEpisodeDate
                        var updatedPodcast = podcast
                        if let latestDate = episodes.compactMap({ $0.publishedDate }).max() {
                            updatedPodcast.lastEpisodeDate = latestDate
                        }
                        updatedPodcasts.append(updatedPodcast)
                    }
                }
            }
            
            // Small delay between batches to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // Process all new episodes
        await processNewEpisodes(allNewEpisodes, allPodcasts: podcasts, updatedPodcasts: updatedPodcasts, episodesByPodcast: episodesByPodcast)
        
        isUpdating = false
        lastUpdateTime = Date()
        print("✅ Background episode update completed")
    }
    
    private func fetchEpisodesForPodcast(_ podcast: Podcast) async -> (Podcast, [Episode]) {
        return await withCheckedContinuation { continuation in
            PodcastService.shared.fetchEpisodes(for: podcast) { episodes in
                continuation.resume(returning: (podcast, episodes))
            }
        }
    }
    
    private func processNewEpisodes(_ newEpisodes: [Episode], allPodcasts: [Podcast], updatedPodcasts: [Podcast], episodesByPodcast: [UUID: [Episode]]) async {
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Update episodes in background
            group.addTask {
                await self.updateEpisodesDatabase(newEpisodes)
            }
            
            // Task 2: Update podcasts with new lastEpisodeDate and artwork
            group.addTask {
                await self.updatePodcastsDatabase(allPodcasts, updatedPodcasts: updatedPodcasts)
            }
            
            // Task 3: Fetch and update podcast artwork in background
            group.addTask {
                await self.updatePodcastArtwork(allPodcasts, podcastsToUpdate: updatedPodcasts)
            }
            
            // Task 4: Refresh episode cache with latest data
            group.addTask {
                await self.refreshEpisodeCache(episodesByPodcast)
            }

            // Task 5: Sort and notify UI on main thread
            group.addTask {
                await self.sortAndNotifyUI()
            }
        }
    }
    
    private func updateEpisodesDatabase(_ newEpisodes: [Episode]) async {
        guard !newEpisodes.isEmpty else { return }
        
        // This operation can be slow, so keep it off the main thread
        sortingQueue.async {
            let episodeViewModel = EpisodeViewModel.shared
            let existingEpisodes = episodeViewModel.episodes
            
            // Create lookup sets for efficient deduplication
            let existingIDs = Set(existingEpisodes.map { $0.id })
            let existingTitlePodcastPairs = Set(existingEpisodes.compactMap { episode -> String? in
                guard let podcastID = episode.podcastID else { return nil }
                return "\(episode.title)-\(podcastID.uuidString)"
            })
            
            // Filter out episodes that already exist (by ID or title+podcast combination)
            let episodesToAdd = newEpisodes.filter { episode in
                // Skip if ID already exists
                if existingIDs.contains(episode.id) {
                    return false
                }
                
                // Skip if same title and podcast already exists (prevents duplicates from re-parsing)
                if let podcastID = episode.podcastID {
                    let titlePodcastKey = "\(episode.title)-\(podcastID.uuidString)"
                    return !existingTitlePodcastPairs.contains(titlePodcastKey)
                }
                
                return true
            }
            
            if !episodesToAdd.isEmpty {
                print("📥 Adding \(episodesToAdd.count) new episodes to database (filtered from \(newEpisodes.count) total)")
                episodeViewModel.addEpisodes(episodesToAdd)
            } else {
                print("📥 No new episodes to add (all \(newEpisodes.count) episodes already exist)")
            }
        }
    }
    
    private func updatePodcastsDatabase(_ allPodcasts: [Podcast], updatedPodcasts: [Podcast]) async {
        guard !updatedPodcasts.isEmpty else { return }
        
        updateQueue.async {
            var mutablePodcasts = allPodcasts
            
            // Update existing podcasts with new lastEpisodeDate
            for updatedPodcast in updatedPodcasts {
                if let index = mutablePodcasts.firstIndex(where: { $0.id == updatedPodcast.id }) {
                    mutablePodcasts[index].lastEpisodeDate = updatedPodcast.lastEpisodeDate
                }
            }
            
            // Save back to storage
            PodcastService.shared.savePodcasts(mutablePodcasts)
        }
    }
    
    private func updatePodcastArtwork(_ allPodcasts: [Podcast], podcastsToUpdate: [Podcast]) async {
        guard !podcastsToUpdate.isEmpty else { return }
        
        var mutablePodcasts = allPodcasts
        var hasUpdates = false
        
        for podcast in podcastsToUpdate {
            // Find the podcast in our saved list
            if let index = mutablePodcasts.firstIndex(where: { $0.id == podcast.id }) {
                // ALWAYS fetch artwork from RSS feed to ensure it's up-to-date.
                if let artworkURL = await EpisodeUpdateService.fetchPodcastArtworkFromRSS_Background(mutablePodcasts[index].feedURL) {
                    // Only update if the new URL is different from the old one
                    if mutablePodcasts[index].artworkURL != artworkURL {
                        mutablePodcasts[index].artworkURL = artworkURL
                        hasUpdates = true
                        print("📸 Updated artwork for podcast: \(mutablePodcasts[index].title) to \(artworkURL.absoluteString)")
                    } else {
                        print("ℹ️ Artwork for podcast: \(mutablePodcasts[index].title) is already up-to-date.")
                    }
                } else {
                    print("⚠️ Could not fetch artwork for podcast: \(mutablePodcasts[index].title) from feed: \(mutablePodcasts[index].feedURL)")
                }
            }
        }
        
        // Save if we have updates
        if hasUpdates {
            PodcastService.shared.savePodcasts(mutablePodcasts)
            print("📸 Saved \(podcastsToUpdate.count) podcast artwork updates")
        }
    }
    
    private static func fetchPodcastArtworkFromRSS_Background(_ feedURL: URL) async -> URL? {
        do {
            // PERFORMANCE FIX: Use proper async/await instead of blocking operations
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            
            // Parse RSS to extract artwork URL
            let parser = RSSParser()
            _ = parser.parseRSS(data: data, podcastID: UUID()) // We don't need episodes here
            
            if let artworkURLString = parser.getPodcastArtworkURL(),
               let artworkURL = URL(string: artworkURLString) {
                return artworkURL
            }
        } catch {
            print("⚠️ Artwork fetch failed for URL: \(feedURL), error: \(error)")
        }
        
        return nil
    }
    
    private func sortAndNotifyUI() async {
        // Force UI refresh by notifying observers
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .episodesUpdated, object: nil)
        }
    }
    
    private func refreshEpisodeCache(_ episodesByPodcast: [UUID: [Episode]]) async {
        let episodeCacheService = EpisodeCacheService.shared

        for (podcastID, episodes) in episodesByPodcast {
            guard !episodes.isEmpty else { continue }
            episodeCacheService.updateCache(episodes, for: podcastID)
            print("💾 Updated cache for podcast: \(podcastID) with \(episodes.count) episodes")
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if episodes need updating based on last update time
    func needsUpdate() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) > updateInterval
    }
    
    /// Get formatted last update time
    func lastUpdateTimeString() -> String {
        guard let lastUpdate = lastUpdateTime else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let episodesUpdated = Notification.Name("episodesUpdated")
}

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
} 
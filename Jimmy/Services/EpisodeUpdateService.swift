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
        // MEMORY FIX: Stop existing timer first to prevent multiple timers
        stopPeriodicUpdates()

        // AUTOMATIC: Episode updates are now triggered automatically by DataFetchCoordinator
        // when app becomes active, podcasts are added, or network becomes available
        print("🎯 Periodic update system initialized - updates will be triggered automatically")
        
        // MEMORY FIX: Use weak self and proper cleanup
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] timer in
            guard let self = self else { 
                timer.invalidate()
                return 
            }
            
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
            
            // AUTOMATIC: Trigger automatic update via DataFetchCoordinator
            // This will be handled automatically by the coordinator's app state observers
            print("🎯 Timer triggered - automatic update will be handled by DataFetchCoordinator")
        }
    }
    
    /// Stop periodic updates
    func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
        print("🛑 Periodic updates stopped")
    }
    
    deinit {
        // MEMORY FIX: Ensure timer is cleaned up
        stopPeriodicUpdates()
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Manually trigger an update (user-initiated only)
    func forceUpdate() {
        // MANUAL TRIGGER: This is the only method that should be called manually by user action
        print("👤 User manually triggered episode update")
        
        Task { @MainActor in
            DataFetchCoordinator.shared.startFetch(
                id: "manual-episode-update",
                operation: {
                    return try await self.updateAllEpisodesThreadSafe()
                },
                onComplete: { result in
                    switch result {
                    case .success(let message):
                        print("✅ Manual episode update completed: \(message)")
                    case .failure(let error):
                        print("❌ Manual episode update failed: \(error)")
                    }
                }
            )
        }
    }
    
    // MARK: - Background Update Logic
    
    /// Thread-safe episode update method using proper critical sections
    private func updateAllEpisodesThreadSafe() async throws -> String {
        // Critical section: Check if already updating
        guard !isUpdating else {
            throw EpisodeUpdateError.alreadyUpdating
        }
        
        // Set updating state in critical section
        await MainActor.run {
            self.isUpdating = true
            self.updateProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                self.isUpdating = false
                self.lastUpdateTime = Date()
            }
        }
        
        let podcasts = PodcastService.shared.loadPodcasts()
        guard !podcasts.isEmpty else {
            throw EpisodeUpdateError.noPodcasts
        }
        
        print("🔄 Starting thread-safe episode update for \(podcasts.count) podcasts")
        
        // Use batch fetch coordinator for better thread management
        return await withCheckedContinuation { continuation in
            let operations = podcasts.map { podcast in
                (
                    id: podcast.id.uuidString,
                    operation: {
                        return try await self.fetchEpisodesForPodcastThreadSafe(podcast)
                    }
                )
            }
            
            Task { @MainActor in
                DataFetchCoordinator.shared.startBatchFetch(
                    batchId: "episode-batch-update",
                    operations: operations,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.updateProgress = progress
                        }
                    },
                    onComplete: { results in
                        Task {
                            await self.processBatchResults(results, podcasts: podcasts)
                            continuation.resume(returning: "Updated \(results.count) podcasts")
                        }
                    }
                )
            }
        }
    }
    
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
        
        // Process podcasts in batches to provide incremental UI updates
        let batchSize = 5 // Fetch 5 podcasts at a time
        let batches = podcasts.chunked(into: batchSize)
        var allNewEpisodes: [Episode] = []
        var updatedPodcasts: [Podcast] = []
        let totalPodcasts = Double(podcasts.count)
        var completedCount = 0
        
        for batch in batches {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                print("📦 Processing batch with podcasts: \(batch.map { "\($0.title) (ID: \($0.id))" })")
                OptimizedPodcastService.shared.batchFetchEpisodes(for: batch) { episodesByPodcast in
                    // Process the results of this batch
                    for (podcastID, episodes) in episodesByPodcast {
                        if !episodes.isEmpty {
                            print("📥 Received \(episodes.count) episodes for podcast ID: \(podcastID)")
                            if let firstEpisode = episodes.first {
                                print("📥 First episode podcastID: \(firstEpisode.podcastID?.uuidString ?? "nil")")
                            }
                            allNewEpisodes.append(contentsOf: episodes)
                            
                            // Find the original podcast to update its metadata
                            if var updatedPodcast = podcasts.first(where: { $0.id == podcastID }) {
                                print("✅ Found matching podcast: \(updatedPodcast.title)")
                                if let latestDate = episodes.compactMap({ $0.publishedDate }).max() {
                                    updatedPodcast.lastEpisodeDate = latestDate
                                }
                                updatedPodcasts.append(updatedPodcast)
                            } else {
                                print("⚠️ No matching podcast found for ID: \(podcastID)")
                                print("📱 Available podcast IDs: \(podcasts.map { $0.id })")
                            }
                        }
                    }
                    
                    // Add new episodes to the view model immediately for progressive UI updates
                    if !allNewEpisodes.isEmpty {
                        print("📥 Adding \(allNewEpisodes.count) episodes to EpisodeRepository")
                        Task { @MainActor in
                            try? await EpisodeRepository.shared.addNewEpisodes(allNewEpisodes)
                        }
                        allNewEpisodes.removeAll() // Clear for the next batch
                    } else {
                        print("⚠️ No episodes found in this batch")
                    }
                    
                    continuation.resume()
                }
            }
            
            // Update progress
            completedCount += batch.count
            let currentProgress = Double(completedCount) / totalPodcasts
            self.updateProgress = currentProgress
            print("📈 Update progress: \(Int(currentProgress * 100))%")
            
            // Small delay between batches to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        // Finalize the update process
        await finalizeUpdate(allPodcasts: podcasts, updatedPodcasts: updatedPodcasts)
        
        isUpdating = false
        lastUpdateTime = Date()
        print("✅ Background episode update completed")
    }

    private func finalizeUpdate(allPodcasts: [Podcast], updatedPodcasts: [Podcast]) async {
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Update podcasts with new lastEpisodeDate and artwork
            group.addTask {
                await self.updatePodcastsDatabase(allPodcasts, updatedPodcasts: updatedPodcasts)
            }
            
            // Task 2: Fetch and update podcast artwork in background
            group.addTask {
                await self.updatePodcastArtwork(allPodcasts, podcastsToUpdate: updatedPodcasts)
            }

            // Task 3: Sort and notify UI on main thread
            group.addTask {
                await self.sortAndNotifyUI()
            }
        }
    }
    
    private func fetchEpisodesForPodcast(_ podcast: Podcast) async -> (Podcast, [Episode]) {
        return await withCheckedContinuation { continuation in
            PodcastService.shared.fetchEpisodes(for: podcast) { episodes in
                continuation.resume(returning: (podcast, episodes))
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
            // Use the new RSSParser with async/await pattern
            let parser = RSSParser(podcastID: UUID()) // Temporary UUID for artwork extraction
            let (_, metadata) = try await parser.parse(from: feedURL)
            
            return metadata.artworkURL
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
    
    // MARK: - Utility Methods
    
    /// Check if episodes need updating based on last update time (used by automatic triggers)
    func needsUpdate() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        
        // Only update if more than 30 minutes have passed (for automatic triggers)
        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
        let minimumUpdateInterval: TimeInterval = 30 * 60 // 30 minutes
        
        return timeSinceLastUpdate > minimumUpdateInterval
    }
    
    /// Get formatted last update time
    func lastUpdateTimeString() -> String {
        guard let lastUpdate = lastUpdateTime else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
    }
    

    
    // MARK: - Automatic Update Methods (Called by DataFetchCoordinator)
    
    /// Fetch episodes for a single podcast - called automatically when podcast is added
    func fetchEpisodesForSinglePodcast(_ podcast: Podcast) async throws -> [Episode] {
        print("🎯 Auto-fetching episodes for: \(podcast.title)")
        
        return await withCheckedContinuation { continuation in
            OptimizedPodcastService.shared.batchFetchEpisodes(for: [podcast]) { episodesByPodcast in
                if let episodes = episodesByPodcast[podcast.id] {
                    // Automatically add episodes to repository
                    Task { @MainActor in
                        try? await EpisodeRepository.shared.addNewEpisodes(episodes)
                        NotificationCenter.default.post(name: .episodesUpdated, object: nil)
                    }
                    continuation.resume(returning: episodes)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Perform automatic periodic update - called when app becomes active
    func performAutomaticUpdate() async throws -> String {
        // Check if update is needed to prevent infinite loops
        guard needsUpdate() else {
            print("🎯 Skipping automatic periodic update - too recent")
            return "Skipped - too recent"
        }
        print("🎯 Performing automatic periodic update")
        return try await updateAllEpisodesThreadSafe()
    }
    
    /// Perform automatic update when network becomes available
    func performNetworkAvailableUpdate() async throws -> String {
        // Check if update is needed to prevent infinite loops
        guard needsUpdate() else {
            print("🎯 Skipping automatic network-available update - too recent")
            return "Skipped - too recent"
        }
        print("🎯 Performing automatic network-available update")
        return try await updateAllEpisodesThreadSafe()
    }
    
    // MARK: - Thread-Safe Helper Methods
    
    /// Fetch episodes for a single podcast in a thread-safe manner (new version)
    private func fetchEpisodesForPodcastThreadSafe(_ podcast: Podcast) async throws -> [Episode] {
        return await withCheckedContinuation { continuation in
            OptimizedPodcastService.shared.batchFetchEpisodes(for: [podcast]) { episodesByPodcast in
                if let episodes = episodesByPodcast[podcast.id] {
                    continuation.resume(returning: episodes)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    /// Process batch results from thread-safe fetch operations
    private func processBatchResults(_ results: [String: Result<[Episode], Error>], podcasts: [Podcast]) async {
        var allNewEpisodes: [Episode] = []
        var updatedPodcasts: [Podcast] = []
        
        for (podcastIdString, result) in results {
            guard let podcastId = UUID(uuidString: podcastIdString),
                  let podcast = podcasts.first(where: { $0.id == podcastId }) else {
                continue
            }
            
            switch result {
            case .success(let episodes):
                if !episodes.isEmpty {
                    print("📥 Received \(episodes.count) episodes for podcast: \(podcast.title)")
                    allNewEpisodes.append(contentsOf: episodes)
                    
                    // Update podcast metadata
                    var updatedPodcast = podcast
                    if let latestDate = episodes.compactMap({ $0.publishedDate }).max() {
                        updatedPodcast.lastEpisodeDate = latestDate
                    }
                    updatedPodcasts.append(updatedPodcast)
                }
            case .failure(let error):
                print("❌ Failed to fetch episodes for podcast \(podcast.title): \(error)")
            }
        }
        
        // Add new episodes to repository
        if !allNewEpisodes.isEmpty {
            print("📥 Adding \(allNewEpisodes.count) episodes to EpisodeRepository")
            Task { @MainActor in
                try? await EpisodeRepository.shared.addNewEpisodes(allNewEpisodes)
            }
        }
        
        // Update podcast database
        if !updatedPodcasts.isEmpty {
            await updatePodcastsDatabase(podcasts, updatedPodcasts: updatedPodcasts)
        }
        
        // Notify UI
        await MainActor.run {
            NotificationCenter.default.post(name: .episodesUpdated, object: nil)
        }
    }
    

}

// MARK: - Notification Extensions

extension Notification.Name {
    static let episodesUpdated = Notification.Name("episodesUpdated")
}

// MARK: - Error Types

enum EpisodeUpdateError: Error, LocalizedError {
    case alreadyUpdating
    case noPodcasts
    case fetchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyUpdating:
            return "Episode update is already in progress"
        case .noPodcasts:
            return "No podcasts found to update"
        case .fetchFailed(let message):
            return "Episode fetch failed: \(message)"
        }
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

 
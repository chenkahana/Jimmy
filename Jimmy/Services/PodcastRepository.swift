import Foundation
import os
import GRDB
import Combine
import CryptoKit

// MARK: - Helper Functions

/// Generate a deterministic UUID based on a string (feedURL)
/// This ensures the same podcast always gets the same UUID across migrations
private func generateDeterministicUUID(from string: String) -> UUID {
    let hash = SHA256.hash(data: Data(string.utf8))
    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
    
    // Take first 32 characters and format as UUID
    let uuidString = String(hashString.prefix(32))
    let formattedUUID = "\(uuidString.prefix(8))-\(uuidString.dropFirst(8).prefix(4))-\(uuidString.dropFirst(12).prefix(4))-\(uuidString.dropFirst(16).prefix(4))-\(uuidString.dropFirst(20).prefix(12))"
    
    return UUID(uuidString: formattedUUID.uppercased()) ?? UUID()
}

/// PodcastRepository is responsible for managing podcast data persistence using GRDB
class PodcastRepository: PodcastRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "PodcastRepository")
    static let shared = PodcastRepository()
    
    private let dbManager: DatabaseManager
    private let cacheStore: MemoryCacheStore
    private let logger = ErrorLogger.shared
    private let changesSubject = PassthroughSubject<PodcastChanges, Never>()
    
    /// Publisher for podcast changes
    var podcastChangesPublisher: AnyPublisher<PodcastChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
    
    private init(dbManager: DatabaseManager = DatabaseManager.shared, cacheStore: MemoryCacheStore = MemoryCacheStore.shared) {
        self.dbManager = dbManager
        self.cacheStore = cacheStore
        
        // Start migration check
        Task {
            await checkAndMigrateIfNeeded()
        }
    }
    
    /// Loads all podcasts from the database
    func loadPodcasts() async -> [Podcast] {
        do {
            return try await fetchPodcasts(ignoreCache: false)
        } catch {
            return []
        }
    }
    
    /// Loads a specific podcast by ID
    func loadPodcast(id: UUID) async -> Podcast? {
        do {
            return try await fetchPodcast(id: id, ignoreCache: false)
        } catch {
            return nil
        }
    }
    
    /// Saves a collection of podcasts to the database
    func savePodcasts(_ podcasts: [Podcast]) async throws {
        try await dbManager.writeAsync { db in
            for podcast in podcasts {
                try podcast.save(db)
                // Update cache
                self.cacheStore.subscriptionCache.insert(podcast, forKey: podcast.id)
            }
        }
        
        // Notify subscribers about the change
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: podcasts, removed: [], updated: []))
        }
    }
    
    /// Adds a single podcast to the database
    func addPodcast(_ podcast: Podcast) async throws {
        try await savePodcasts([podcast])
    }
    
    /// Updates a podcast in the database
    func updatePodcast(_ podcast: Podcast) async throws {
        try await dbManager.writeAsync { [self] db in
            try podcast.update(db)
            // Update cache
            cacheStore.subscriptionCache.insert(podcast, forKey: podcast.id)
        }
        
        // Notify subscribers about the change
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: [], removed: [], updated: [podcast]))
        }
    }
    
    /// Deletes a podcast from the database
    func deletePodcast(id: UUID) async throws {
        try await dbManager.writeAsync { [self] db in
            try Podcast.deleteOne(db, key: Podcast.dbKey(for: id))
            // Remove from cache
            cacheStore.subscriptionCache.removeValue(forKey: id)
        }
        
        // Notify subscribers about the change
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: [], removed: [], updated: []))
        }
    }
    
    /// Migrates data from legacy UserDefaults storage to GRDB if needed
    private func checkAndMigrateIfNeeded() async {
        let userDefaults = UserDefaults.standard

        // Check 1: If migration is already marked as fully completed, we're done.
        if userDefaults.bool(forKey: "migration_completed_legacy") {
            return
        }

        // Check 2: If migration was previously ATTEMPTED but not marked COMPLETED.
        if userDefaults.bool(forKey: "migration_attempted_legacy") {
            userDefaults.set(true, forKey: "migration_completed_legacy")
            return
        }
        
        // Check 3: If user has intentionally cleared all podcasts, respect that choice.
        if userDefaults.bool(forKey: "user_cleared_all_podcasts") {
            userDefaults.set(true, forKey: "migration_attempted_legacy")
            userDefaults.set(true, forKey: "migration_completed_legacy")
            return
        }

        // Check 4: This is a first run or migration has never been attempted.
        userDefaults.set(true, forKey: "migration_attempted_legacy")

        do {
            let hasPodcasts = try await dbManager.readAsync { db in
                try Podcast.fetchCount(db) > 0
            }

            if !hasPodcasts {
                var podcastsToMigrate: [Podcast] = []

                if let data = userDefaults.data(forKey: "saved_podcasts"),
                   let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
                    podcastsToMigrate.append(contentsOf: podcasts)
                }
                
                let fileStorage = FileStorage.shared
                if let filePodcasts = fileStorage.load([Podcast].self, from: "podcasts.json") {
                    podcastsToMigrate.append(contentsOf: filePodcasts)
                }

                if !podcastsToMigrate.isEmpty {
                    var uniquePodcasts: [Podcast] = []
                    var seenFeedURLs = Set<URL>()
                    for podcast in podcastsToMigrate {
                        if !seenFeedURLs.contains(podcast.feedURL) {
                            uniquePodcasts.append(podcast)
                            seenFeedURLs.insert(podcast.feedURL)
                        }
                    }

                    try await dbManager.writeAsync { db in
                        for podcast in uniquePodcasts {
                            try podcast.save(db)
                            self.cacheStore.subscriptionCache[podcast.id] = podcast
                        }
                    }
                }
            }
            
            userDefaults.set(true, forKey: "migration_completed_legacy")
        } catch {
            userDefaults.set(true, forKey: "migration_completed_legacy") // Mark completed even on error.
        }
    }
    
    /// Migrate existing podcasts to use deterministic UUIDs based on their feedURL
    /// This fixes the unsubscribe issue for podcasts that were created before the deterministic UUID fix
    private func migrateExistingPodcastUUIDs() async {
        let userDefaults = UserDefaults.standard
        if userDefaults.bool(forKey: "uuid_migration_completed_legacy_v2") {
            return
        }
        
        userDefaults.set(true, forKey: "uuid_migration_completed_legacy_v2")
    }
    
    // MARK: - PodcastRepositoryProtocol Methods
    
    func fetchPodcasts(ignoreCache: Bool) async throws -> [Podcast] {
        // Delegate to existing loadPodcasts method but throw on error
        let podcasts = await loadPodcasts()
        return podcasts
    }
    
    func fetchPodcast(id: UUID, ignoreCache: Bool) async throws -> Podcast? {
        // Delegate to existing loadPodcast method
        return await loadPodcast(id: id)
    }
    
    func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // Use the network manager to fetch RSS feed data
        let rssData = try await UnifiedNetworkService.shared.fetchData(
            from: feedURL,
            timeout: 30.0
        )
        
        // Parse the RSS data to extract podcast metadata and episodes
        let parser = ConcreteRSSParser()
        let podcastID = UUID()
        let (episodes, metadata) = try await parser.parse(data: rssData, podcastID: podcastID, feedURL: feedURL)
        
        // Create podcast from metadata
        let podcast = Podcast(
            id: podcastID,
            title: metadata.title ?? "Unknown Podcast",
            author: metadata.author ?? "Unknown Author",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max()
        )
        
        return (podcast, episodes)
    }
    
    func previewPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // Use the network manager to fetch RSS feed data
        let rssData = try await UnifiedNetworkService.shared.fetchData(
            from: feedURL,
            timeout: 30.0
        )
        
        // Parse the RSS data to extract podcast metadata and episodes
        let parser = ConcreteRSSParser()
        let podcastID = UUID()
        let (episodes, metadata) = try await parser.parse(data: rssData, podcastID: podcastID, feedURL: feedURL)
        
        // Create podcast from metadata
        let podcast = Podcast(
            id: podcastID,
            title: metadata.title ?? "Unknown Podcast",
            author: metadata.author ?? "Unknown Author",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max()
        )
        
        Self.logger.info("Podcast preview loaded: \(podcast.title) with \(episodes.count) episodes (not saved)")
        
        return (podcast, episodes)
    }
    
    func deletePodcastData(id: UUID) async throws {
        let podcast = try await fetchPodcast(id: id, ignoreCache: false)
        
        let deleted = try await dbManager.writeAsync { db in
            // FK cascade will automatically delete associated episodes
            try Podcast.deleteOne(db, key: Podcast.dbKey(for: id))
        }
        
        if deleted, let removedPodcast = podcast {
            // Remove from cache
            cacheStore.subscriptionCache.removeValue(forKey: id)
            
            Task { @MainActor in
                changesSubject.send(PodcastChanges(added: [], removed: [removedPodcast], updated: []))
            }
        }
    }
} 
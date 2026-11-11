import Foundation
import Combine
import GRDB
import os
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

// MARK: - GRDB Repository Implementations with Layered Caching

/// GRDB-based implementation of the subscription repository protocol with layered caching.
final class GRDBSubscriptionRepository: SubscriptionRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "GRDBRepositories")
    private let dbManager: DatabaseManager
    private let cacheStore: MemoryCacheStore
    private let networkRepository: NetworkRepositoryProtocol
    private let changesSubject = PassthroughSubject<[Podcast], Never>()
    
    // Staleness intervals
    private let subscriptionStalenessInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    init(
        dbManager: DatabaseManager,
        cacheStore: MemoryCacheStore,
        networkRepository: NetworkRepositoryProtocol
    ) {
        self.dbManager = dbManager
        self.cacheStore = cacheStore
        self.networkRepository = networkRepository
    }

    func fetchSubscriptions(ignoreCache: Bool = false) async throws -> [Podcast] {
        // Check and migrate if needed
        await checkAndMigrateIfNeeded()
        
        let podcasts = try await dbManager.readAsync { db in
            try Podcast.fetchAll(db)
        }
        
        // Update cache
        for podcast in podcasts {
            cacheStore.subscriptionCache[podcast.id] = podcast
        }
        
        return podcasts
    }

    func fetchSubscription(id: UUID, ignoreCache: Bool) async throws -> Podcast? {
        // 1. Check memory cache first
        if !ignoreCache, let cached = cacheStore.subscriptionCache[id] {
            // Check staleness and refresh in background if needed
            if isStale(podcast: cached) {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshSubscription(cached)
                }
            }
            return cached
        }
        
        // 2. Check database
        if let fromDB = try await dbManager.readAsync({ db in try Podcast.fetchOne(db, key: Podcast.dbKey(for: id)) }) {
            cacheStore.subscriptionCache[id] = fromDB
            
            // Check staleness and refresh in background if needed
            if !ignoreCache && isStale(podcast: fromDB) {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshSubscription(fromDB)
                }
            }
            
            return fromDB
        }
        
        return nil
    }

    func addSubscription(_ podcast: Podcast) async throws {
        // Write-through caching: update all layers
        try await dbManager.writeAsync { db in
            try podcast.save(db)
        }
        
        // Update memory cache
        cacheStore.subscriptionCache[podcast.id] = podcast
        
        // Clear the "user cleared all podcasts" flag since user is now adding podcasts again
        if UserDefaults.standard.bool(forKey: "user_cleared_all_podcasts") {
            UserDefaults.standard.set(false, forKey: "user_cleared_all_podcasts")
            _ = UserDefaults.standard.synchronize()
        }
        
        // No need to invalidate "all" cache since we store individual entries
        
        // Notify subscribers
        Task { @MainActor in
            let allPodcasts = try? await fetchSubscriptions(ignoreCache: false)
            changesSubject.send(allPodcasts ?? [])
        }
    }

    func removeSubscription(id: UUID) async throws {
        let key = Podcast.dbKey(for: id)
        
        // First check if the podcast exists
        _ = try await dbManager.readAsync { db in
            try Podcast.fetchOne(db, key: key)
        }
        
        let deleted = try await dbManager.writeAsync { db in
            try Podcast.deleteOne(db, key: key)
        }
        
        if deleted {
            // Update memory cache
            cacheStore.subscriptionCache.removeValue(forKey: id)
            
            // Check if this was the last podcast in the database
            let remainingCount = try await dbManager.readAsync { db in
                try Podcast.fetchCount(db)
            }
            
            if remainingCount == 0 {
                // User has unsubscribed from all podcasts - set flag to prevent migration re-import
                UserDefaults.standard.set(true, forKey: "user_cleared_all_podcasts")
                _ = UserDefaults.standard.synchronize()
            }
            
            // Verify deletion by checking if it still exists
            let verifyDeleted = try await dbManager.readAsync { db in
                try Podcast.fetchOne(db, key: key)
            }
            
            if verifyDeleted == nil {
            } else {
            }
            
            // Notify subscribers
            Task { @MainActor in
                let allPodcasts = try? await fetchSubscriptions(ignoreCache: false)
                changesSubject.send(allPodcasts ?? [])
            }
        } else {
        }
    }

    func removeAllSubscriptions() async throws {
        // Remove all data from database in the correct order (episodes before podcasts due to foreign keys)
        try await dbManager.writeAsync { db in
            // Delete episodes first (they have foreign key to podcasts)
            try Episode.deleteAll(db)
            Self.logger.info("Repository: Deleted all episodes from database")
            
            // Delete playback states
            try PlaybackState.deleteAll(db)
            Self.logger.info("Repository: Deleted all playback states from database")
            
            // Delete podcasts last
            try Podcast.deleteAll(db)
            Self.logger.info("Repository: Deleted all podcasts from database")
        }
        
        // Clear memory cache
        cacheStore.subscriptionCache.removeAllValues()
        Self.logger.info("Repository: Cleared memory caches")
        
        // Set flag to prevent migration re-import since user intentionally cleared all podcasts
        UserDefaults.standard.set(true, forKey: "user_cleared_all_podcasts")
        _ = UserDefaults.standard.synchronize()
        
        Self.logger.info("Repository: Successfully deleted all subscriptions, episodes, and playback states")
        
        // Notify subscribers with empty array
        Task { @MainActor in
            changesSubject.send([])
        }
    }

    func updateSubscription(_ podcast: Podcast) async throws {
        // Write-through caching: update all layers
        try await dbManager.writeAsync { db in
            try podcast.save(db)
        }
        
        // Update memory cache
        cacheStore.subscriptionCache[podcast.id] = podcast
        
        // Notify subscribers
        Task { @MainActor in
            let allPodcasts = try? await fetchSubscriptions(ignoreCache: false)
            changesSubject.send(allPodcasts ?? [])
        }
    }

    func isStale(podcast: Podcast) -> Bool {
        guard let lastFetched = podcast.lastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) > subscriptionStalenessInterval
    }

    var subscriptionChangesPublisher: AnyPublisher<[Podcast], Never> {
        changesSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    /// Migrates data from legacy UserDefaults storage to GRDB if needed
    private func checkAndMigrateIfNeeded() async {
        let userDefaults = UserDefaults.standard

        // Check 1: If migration is already marked as fully completed, we're done.
        if userDefaults.bool(forKey: "migration_completed") {
            // For robustness, ensure 'migration_attempted' is also true if 'completed' is true.
            if !userDefaults.bool(forKey: "migration_attempted") {
                 userDefaults.set(true, forKey: "migration_attempted")
                 // No critical need to synchronize here as 'completed' is the main gate.
            }
            
            // CRITICAL: Check if we need to migrate existing podcasts to deterministic UUIDs
            await migrateExistingPodcastUUIDs()
            return
        }

        // Check 2: If migration was previously ATTEMPTED but not marked COMPLETED.
        if userDefaults.bool(forKey: "migration_attempted") {
            userDefaults.set(true, forKey: "migration_completed")
            _ = userDefaults.synchronize()
            
            // CRITICAL: Check for UUID migration even if legacy migration was just completed.
            await migrateExistingPodcastUUIDs()
            return
        }
        
        // Check 3: If user has previously unsubscribed from ALL podcasts, respect that choice.
        // Don't re-import their old library. They can re-add manually or re-import from a file.
        if userDefaults.bool(forKey: "user_cleared_all_podcasts") {
            userDefaults.set(true, forKey: "migration_attempted")
            userDefaults.set(true, forKey: "migration_completed")
            _ = userDefaults.synchronize()
            return
        }

        // Check 4: This is a first run or migration has never been attempted.
        userDefaults.set(true, forKey: "migration_attempted")

        // First, check if the database is already populated.
        // This can happen if the user used the app before this migration logic was added.
        let podcastCount = try? await dbManager.readAsync { db in
            try Podcast.fetchCount(db)
        }

        if let count = podcastCount, count > 0 {
            // Database already contains podcasts. No need to migrate from legacy sources.
            // Mark migration as completed to prevent this check from running again.
            userDefaults.set(true, forKey: "migration_completed")
             _ = userDefaults.synchronize()
            
            // CRITICAL: Even if we don't migrate from legacy, we MUST check for UUID migration
            // for the existing data.
            await migrateExistingPodcastUUIDs()
            return
        }
        
        // If we reach here, the database is empty. Proceed with migration from legacy sources.
        
        // Load from legacy UserDefaults
        if let data = userDefaults.data(forKey: "saved_podcasts"),
           let podcasts = try? JSONDecoder().decode([Podcast].self, from: data) {
            
            try? await dbManager.writeAsync { db in
                for podcast in podcasts {
                    try podcast.save(db)
                }
            }
        }
        
        // After attempting migration, mark as completed to prevent re-runs.
        userDefaults.set(true, forKey: "migration_completed")
        _ = userDefaults.synchronize()
        
        // FINAL: Check for UUID migration after any potential legacy migration.
        await migrateExistingPodcastUUIDs()
    }
    
    /// Migrate existing podcasts to use deterministic UUIDs based on their feedURL
    /// This fixes the unsubscribe issue for podcasts that were created before the deterministic UUID fix
    private func migrateExistingPodcastUUIDs() async {
        let userDefaults = UserDefaults.standard
        
        // Check if UUID migration has already been completed
        if userDefaults.bool(forKey: "uuid_migration_completed_v2") {
            return
        }
        
        // Migration to deterministic UUIDs can cause foreign key constraint failures
        // if not handled carefully. For now, we will disable this migration
        // until a safer strategy is developed.
        // This prevents crashes for existing users.
        userDefaults.set(true, forKey: "uuid_migration_completed_v2")
        return
        
        do {
            let existingPodcasts = try await dbManager.readAsync { db in
                try Podcast.fetchAll(db)
            }
            
            if existingPodcasts.isEmpty {
                userDefaults.set(true, forKey: "uuid_migration_completed_v2")
                return
            }
            
            var migratedCount = 0
            
            for oldPodcast in existingPodcasts {
                let deterministicUUID = generateDeterministicUUID(from: oldPodcast.feedURL.absoluteString)
                if oldPodcast.id == deterministicUUID {
                    continue // Already correct
                }
                
                migratedCount += 1
                
                try await dbManager.writeAsync { db in
                    // Turn off foreign keys
                    _ = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
                    try db.execute(sql: "PRAGMA foreign_keys = OFF")
                    _ = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")

                    // Update podcast table
                    try db.execute(
                        sql: "UPDATE podcasts SET id = ? WHERE id = ?",
                        arguments: [deterministicUUID.uuidString.uppercased(), oldPodcast.id.uuidString.uppercased()]
                    )
                    
                    // Update episodes table
                    _ = try Episode.filter(Column("podcastID") == oldPodcast.id).fetchCount(db)
                    
                    try db.execute(
                        sql: "UPDATE episodes SET podcastID = ? WHERE podcastID = ?",
                        arguments: [deterministicUUID.uuidString.uppercased(), oldPodcast.id.uuidString.uppercased()]
                    )
                    _ = db.changesCount
                    
                    // Update playback_states table
                    try db.execute(
                        sql: "UPDATE playback_states SET episodeID IN (SELECT id FROM episodes WHERE podcastID = ?) WHERE episodeID IN (SELECT id FROM episodes WHERE podcastID = ?)",
                        arguments: [deterministicUUID.uuidString.uppercased(), oldPodcast.id.uuidString.uppercased()]
                    )
                    _ = db.changesCount
                    
                    
                    _ = db.changesCount
                    
                    
                    
                    // Re-enable foreign keys
                    try db.execute(sql: "PRAGMA foreign_keys = ON")
                    _ = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
                }
            }
            
            if migratedCount > 0 {
            } else {
            }
            
            userDefaults.set(true, forKey: "uuid_migration_completed_v2")
            
        } catch is DatabaseError {
        } catch {
        }
    }
    
    private func refreshStaleSubscriptions(_ podcasts: [Podcast]) async {
        for podcast in podcasts {
            await refreshSubscription(podcast)
        }
    }
    
    private func refreshSubscription(_ podcast: Podcast) async {
        do {
            let (data, etag, lastModified) = try await networkRepository.fetchRSSFeed(
                from: podcast.feedURL,
                etag: podcast.etag,
                lastModified: podcast.lastFetched
            )
            
            // Update podcast with new metadata
            var updatedPodcast = podcast
            updatedPodcast.etag = etag
            updatedPodcast.lastFetched = Date()
            
            try await updateSubscription(updatedPodcast)
        } catch {
            // Silently fail for background refresh
            // print("Failed to refresh subscription \(podcast.title): \(error)")
        }
    }
}

/// GRDB-based implementation of the podcast repository protocol.
final class GRDBPodcastRepository: PodcastRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "GRDBRepositories")
    private let dbManager: DatabaseManager
    private let cacheStore: MemoryCacheStore
    private let networkRepository: NetworkRepositoryProtocol
    private let rssParser: RSSParserProtocol
    private let changesSubject = PassthroughSubject<PodcastChanges, Never>()

    init(
        dbManager: DatabaseManager,
        cacheStore: MemoryCacheStore,
        networkRepository: NetworkRepositoryProtocol,
        rssParser: RSSParserProtocol
    ) {
        self.dbManager = dbManager
        self.cacheStore = cacheStore
        self.networkRepository = networkRepository
        self.rssParser = rssParser
    }

    func fetchPodcasts(ignoreCache: Bool) async throws -> [Podcast] {
        // Fetch from the database as the primary source of truth.
        let fromDB = try await dbManager.readAsync { db in
            try Podcast.fetchAll(db)
        }
        
        // Even if the DB is empty, we don't treat it as an error, just return empty.
        if !fromDB.isEmpty {
            // Update memory cache with the results from the database.
            for podcast in fromDB {
                cacheStore.subscriptionCache[podcast.id] = podcast
            }
        }
        
        return fromDB
    }

    func fetchPodcast(id: UUID, ignoreCache: Bool) async throws -> Podcast? {
        // 1. Check memory cache first
        if !ignoreCache, let cached = cacheStore.subscriptionCache[id] {
            return cached
        }
        
        // 2. Check database
        if let fromDB = try await dbManager.readAsync({ db in try Podcast.fetchOne(db, key: Podcast.dbKey(for: id)) }) {
            cacheStore.subscriptionCache[id] = fromDB
            return fromDB
        }
        
        return nil
    }

    func fetchPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // First, check if podcast already exists in database by feedURL
        let existingPodcast = try await dbManager.readAsync { db in
            try Podcast.filter(Podcast.Columns.feedURL == feedURL).fetchOne(db)
        }
        
        if let existing = existingPodcast {
            // Podcast already exists, fetch its episodes and return
            let episodes = try await dbManager.readAsync { db in
                try Episode.filter(Episode.Columns.podcastID == existing.id).fetchAll(db)
            }
            return (existing, episodes)
        }
        
        // Podcast doesn't exist, fetch from network and save
        let (rssData, etag, lastModified) = try await networkRepository.fetchRSSFeed(from: feedURL, etag: nil, lastModified: nil)
        let podcastID = UUID() // Generate a new ID for the new podcast
        
        let (episodes, metadata) = try await rssParser.parse(data: rssData, podcastID: podcastID, feedURL: feedURL)
        
        guard let title = metadata.title, !title.isEmpty else {
            throw PodcastRepositoryError.invalidRSSFeed
        }
        
        let podcast = Podcast(
            id: podcastID,
            title: title,
            author: metadata.author ?? "Unknown",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max(),
            etag: etag,
            lastFetched: Date()
        )
        
        // Save the new podcast and its episodes to the database in a single transaction
        Self.logger.info("Repository: Saving podcast \(podcast.title) with \(episodes.count) episodes")
        try await dbManager.writeAsync { db in
            // First save the podcast
            try podcast.save(db)
            Self.logger.info("Repository: Podcast saved successfully")
            
            // Then save all episodes in the same transaction using GRDB's save method
            for (index, episode) in episodes.enumerated() {
                // Ensure the episode has the correct podcastID
                var episodeToSave = episode
                episodeToSave.podcastID = podcast.id
                
                try episodeToSave.save(db)
                
                if (index + 1) % 100 == 0 || index == episodes.count - 1 {
                    Self.logger.debug("Repository: Saved \(index + 1)/\(episodes.count) episodes")
                }
            }
            
            // Update memory cache
            self.cacheStore.subscriptionCache[podcast.id] = podcast
            Self.logger.info("Repository: All episodes saved successfully")
        }
        
        // Notify about the new podcast being added
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: [podcast], removed: [], updated: []))
        }

        return (podcast, episodes)
    }

    func previewPodcastWithEpisodes(from feedURL: URL) async throws -> (Podcast, [Episode]) {
        // For preview, always fetch from network without checking database
        let (rssData, etag, lastModified) = try await networkRepository.fetchRSSFeed(from: feedURL, etag: nil, lastModified: nil)
        let podcastID = UUID() // Generate a temporary ID for preview
        
        let (episodes, metadata) = try await rssParser.parse(data: rssData, podcastID: podcastID, feedURL: feedURL)
        
        guard let title = metadata.title, !title.isEmpty else {
            throw PodcastRepositoryError.invalidRSSFeed
        }
        
        let podcast = Podcast(
            id: podcastID,
            title: title,
            author: metadata.author ?? "Unknown",
            description: metadata.description ?? "",
            feedURL: feedURL,
            artworkURL: metadata.artworkURL,
            lastEpisodeDate: episodes.compactMap(\.publishedDate).max(),
            etag: etag,
            lastFetched: Date()
        )
        
        // DO NOT save to database - this is preview only
        Self.logger.info("Podcast preview loaded: \(podcast.title) with \(episodes.count) episodes (not saved)")
        
        return (podcast, episodes)
    }

    func savePodcasts(_ podcasts: [Podcast]) async throws {
        try await dbManager.writeAsync { db in
            for podcast in podcasts {
                try podcast.save(db)
                // Update memory cache
                self.cacheStore.subscriptionCache[podcast.id] = podcast
            }
        }
        
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: [], removed: [], updated: podcasts))
        }
    }

    func addPodcast(_ podcast: Podcast) async throws {
        try await savePodcasts([podcast])
        Task { @MainActor in
            changesSubject.send(PodcastChanges(added: [podcast], removed: [], updated: []))
        }
    }

    func deletePodcastData(id: UUID) async throws {
        let podcast = try await fetchPodcast(id: id, ignoreCache: false)
        
        let deleted = try await dbManager.writeAsync { db in
            // FK cascade will automatically delete associated episodes
            try Podcast.deleteOne(db, key: Podcast.dbKey(for: id))
        }
        
        if deleted, let removedPodcast = podcast {
            cacheStore.subscriptionCache.removeValue(forKey: id)
            // Clear episode cache for this podcast
            cacheStore.clearEpisodePages(for: id)
            Task { @MainActor in
                changesSubject.send(PodcastChanges(added: [], removed: [removedPodcast], updated: []))
            }
        }
    }

    func updatePodcast(_ podcast: Podcast) async throws {
        try await savePodcasts([podcast])
    }

    var podcastChangesPublisher: AnyPublisher<PodcastChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
}

/// GRDB-based implementation of the episode repository protocol with enhanced caching.
final class GRDBEpisodeRepository: EpisodeRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "GRDBRepositories")
    private let dbManager: DatabaseManager
    private let cacheStore: MemoryCacheStore
    private let networkRepository: NetworkRepositoryProtocol
    private let rssParser: RSSParserProtocol
    private let changesSubject = PassthroughSubject<CleanEpisodeChanges, Never>()
    
    // Staleness intervals
    private let episodeStalenessInterval: TimeInterval = 60 * 60 // 1 hour

    // Private struct for database representation of an episode
    private struct EpisodeRecord: Codable, PersistableRecord, FetchableRecord {
        static var databaseTableName: String = "episodes"
        
        let id: UUID
        let podcastID: UUID
        let title: String
        let description: String?
        let audioURL: URL?
        let publishedDate: Date?
        let duration: TimeInterval?
        let artworkURL: URL?
        let played: Bool
        let isNew: Bool
        let localFileURL: URL?
        let playbackPosition: Double
        let lastFetched: Date?
        let status: Int // NEW: Episode status as integer
        
        /// Safe initializer that enforces podcastID is provided explicitly
        init(from episode: Episode, podcastID: UUID) {
            self.id = episode.id
            self.podcastID = podcastID
            self.title = episode.title
            self.description = episode.description
            self.audioURL = episode.audioURL
            self.publishedDate = episode.publishedDate
            self.duration = episode.duration
            self.artworkURL = episode.artworkURL
            self.played = episode.played
            self.isNew = episode.isNew
            self.localFileURL = episode.localFileURL
            self.playbackPosition = episode.playbackPosition
            self.lastFetched = Date()
            self.status = episode.status.rawValue
        }
        
        /// Legacy initializer - marked private to prevent misuse
        private init(from episode: Episode) {
            assert(episode.podcastID != nil, "Episode must carry podcastID before save")
            self.id = episode.id
            self.podcastID = episode.podcastID!
            self.title = episode.title
            self.description = episode.description
            self.audioURL = episode.audioURL
            self.publishedDate = episode.publishedDate
            self.duration = episode.duration
            self.artworkURL = episode.artworkURL
            self.played = episode.played
            self.isNew = episode.isNew
            self.localFileURL = episode.localFileURL
            self.playbackPosition = episode.playbackPosition
            self.lastFetched = Date()
            self.status = episode.status.rawValue
        }
        
        func toEpisode() -> Episode {
            return Episode(
                id: id,
                title: title,
                podcastID: podcastID,
                publishedDate: publishedDate,
                duration: duration,
                artworkURL: artworkURL,
                description: description,
                audioURL: audioURL,
                played: played,
                isNew: isNew,
                localFileURL: localFileURL,
                playbackPosition: playbackPosition,
                lastFetched: lastFetched,
                status: EpisodeStatus(rawValue: status)
            )
        }
    }

    init(
        dbManager: DatabaseManager,
        cacheStore: MemoryCacheStore,
        networkRepository: NetworkRepositoryProtocol,
        rssParser: RSSParserProtocol
    ) {
        self.dbManager = dbManager
        self.cacheStore = cacheStore
        self.networkRepository = networkRepository
        self.rssParser = rssParser
    }

    func fetchPage(podcastID: UUID, cursor: String?, limit: Int, ignoreCache: Bool) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?) {
        let page = Int(cursor ?? "1") ?? 1
        let pageKey = EpisodePageKey(podcastID: podcastID, page: page)
        
        // 1. Check memory cache first (unless ignoring cache)
        if !ignoreCache, let cachedEpisodes = cacheStore.episodePageCache[pageKey] {
            // Check staleness and refresh in background if needed
            if isStale(podcastID: podcastID) {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshEpisodesConditional(for: podcastID)
                }
            }
            
            let episodesWithPlayback = try await addPlaybackStates(to: cachedEpisodes)
            let nextCursor = cachedEpisodes.count == limit ? String(page + 1) : nil
            return (episodesWithPlayback, nextCursor)
        }
        
        // 2. Check database
        let offset = (page - 1) * limit
        let episodeRecords = try await dbManager.readAsync { db in
            try EpisodeRecord
                .filter(Column("podcastID") == podcastID)
                .order(Column("publishedDate").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
        
        if !episodeRecords.isEmpty {
            let episodes = episodeRecords.map { $0.toEpisode() }
            
            // Update memory cache
            cacheStore.episodePageCache[pageKey] = episodes
            
            // Check staleness and refresh in background if needed
            if !ignoreCache && isStale(podcastID: podcastID) {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshEpisodesConditional(for: podcastID)
                }
            }
            
            let episodesWithPlayback = try await addPlaybackStates(to: episodes)
            let nextCursor = episodes.count == limit ? String(page + 1) : nil
            return (episodesWithPlayback, nextCursor)
        }
        
        // 3. Fetch from network if not in cache or database
        return try await fetchPageFromNetwork(podcastID: podcastID, page: page, limit: limit)
    }

    /// Phase 5: Conditional GET support for episode fetching
    func fetchPageConditional(
        podcastID: UUID, 
        cursor: String?, 
        limit: Int, 
        etag: String?, 
        lastModified: String?
    ) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?, newEtag: String?, newLastModified: String?)? {
        
        // Get podcast to check feed URL
        guard let podcast = try await dbManager.readAsync({ db in 
            try Podcast.fetchOne(db, key: Podcast.dbKey(for: podcastID)) 
        }) else {
            throw EpisodeRepositoryError.podcastNotFound
        }
        
        // Check if feed has been modified using conditional GET
        do {
            let (rssData, newEtag, newLastModified) = try await networkRepository.fetchRSSFeedConditional(
                from: podcast.feedURL,
                etag: etag,
                lastModified: lastModified
            )
            
            // If we get data, the feed was modified
            if let data = rssData {
                // Parse new episodes
                let (episodes, _) = try await rssParser.parse(data: data, podcastID: podcastID, feedURL: podcast.feedURL)
                
                // Save to database and cache
                try await saveEpisodes(episodes, for: podcastID)
                
                // Update podcast with new headers
                var updatedPodcast = podcast
                updatedPodcast.etag = newEtag
                updatedPodcast.lastFetched = Date()
                try await dbManager.writeAsync { db in
                    try updatedPodcast.save(db)
                }
                
                // Return paginated results
                let page = Int(cursor ?? "1") ?? 1
                let startIndex = (page - 1) * limit
                let endIndex = min(startIndex + limit, episodes.count)
                
                if startIndex < episodes.count {
                    let pageEpisodes = Array(episodes[startIndex..<endIndex])
                    let episodesWithPlayback = try await addPlaybackStates(to: pageEpisodes)
                    let nextCursor = endIndex < episodes.count ? String(page + 1) : nil
                    
                    return (episodesWithPlayback, nextCursor, newEtag, newLastModified)
                } else {
                    return ([], nil, newEtag, newLastModified)
                }
            } else {
                // 304 Not Modified - return nil to indicate no changes
                return nil
            }
            
        } catch FetchError.notModified {
            // 304 Not Modified - return nil to indicate no changes
            return nil
        } catch {
            // On error, fallback to regular fetch
            let (episodes, nextCursor) = try await fetchPage(podcastID: podcastID, cursor: cursor, limit: limit, ignoreCache: false)
            return (episodes, nextCursor, nil, nil)
        }
    }
    
    /// Phase 5: Refresh episodes using conditional GET
    private func refreshEpisodesConditional(for podcastID: UUID) async {
        do {
            guard let podcast = try await dbManager.readAsync({ db in 
                try Podcast.fetchOne(db, key: Podcast.dbKey(for: podcastID)) 
            }) else {
                return
            }
            
            // Use stored ETag and lastFetched for conditional GET
            let lastModifiedString: String?
            if let lastFetched = podcast.lastFetched {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                lastModifiedString = formatter.string(from: lastFetched)
            } else {
                lastModifiedString = nil
            }
            
            let (rssData, newEtag, _) = try await networkRepository.fetchRSSFeedConditional(
                from: podcast.feedURL,
                etag: podcast.etag,
                lastModified: lastModifiedString
            )
            
            // Only process if feed was modified
            if let data = rssData {
                let (episodes, _) = try await rssParser.parse(data: data, podcastID: podcastID, feedURL: podcast.feedURL)
                
                // Save new episodes
                try await saveEpisodes(episodes, for: podcastID)
                
                // Update podcast headers
                var updatedPodcast = podcast
                updatedPodcast.etag = newEtag
                updatedPodcast.lastFetched = Date()
                try await dbManager.writeAsync { db in
                    try updatedPodcast.save(db)
                }
                
                // Clear memory cache to force refresh
                cacheStore.clearEpisodePages(for: podcastID)
                
                // Notify of changes
                Task { @MainActor in
                    let episodesWithPlayback = episodes.map { episode in
                        EpisodeWithPlaybackState(
                            episode: episode,
                            playbackState: PlaybackState(
                                episodeID: episode.id,
                                position: 0.0,
                                finished: false
                            )
                        )
                    }
                    changesSubject.send(CleanEpisodeChanges(
                        podcastID: podcastID, 
                        added: episodesWithPlayback, 
                        removed: [], 
                        updated: []
                    ))
                }
            }
            
        } catch FetchError.notModified {
            // Feed not modified, no action needed
            return
        } catch {
            // On error, log but don't crash
            Self.logger.error("Failed to refresh episodes conditionally: \(error)")
        }
    }

    /// Fetch episodes from network when not available in cache or database
    private func fetchPageFromNetwork(podcastID: UUID, page: Int, limit: Int) async throws -> ([EpisodeWithPlaybackState], nextCursor: String?) {
        // Get podcast to access feed URL
        guard let podcast = try await dbManager.readAsync({ db in 
            try Podcast.fetchOne(db, key: Podcast.dbKey(for: podcastID)) 
        }) else {
            throw EpisodeRepositoryError.podcastNotFound
        }
        
        // Fetch RSS data from network
        let (rssData, etag, _) = try await networkRepository.fetchRSSFeed(
            from: podcast.feedURL,
            etag: podcast.etag,
            lastModified: podcast.lastFetched
        )
        
        // Parse episodes
        let (episodes, _) = try await rssParser.parse(data: rssData, podcastID: podcastID, feedURL: podcast.feedURL)
        
        // Save episodes to database
        try await saveEpisodes(episodes, for: podcastID)
        
        // Update podcast with new headers
        var updatedPodcast = podcast
        updatedPodcast.etag = etag
        updatedPodcast.lastFetched = Date()
        try await dbManager.writeAsync { db in
            try updatedPodcast.save(db)
        }
        
        // Return paginated results
        let startIndex = (page - 1) * limit
        let endIndex = min(startIndex + limit, episodes.count)
        
        if startIndex < episodes.count {
            let pageEpisodes = Array(episodes[startIndex..<endIndex])
            let episodesWithPlayback = try await addPlaybackStates(to: pageEpisodes)
            let nextCursor = endIndex < episodes.count ? String(page + 1) : nil
            
            // Update memory cache
            let pageKey = EpisodePageKey(podcastID: podcastID, page: page)
            cacheStore.episodePageCache[pageKey] = pageEpisodes
            
            return (episodesWithPlayback, nextCursor)
        } else {
            return ([], nil)
        }
    }
    
    /// Save episodes to database with write-through caching
    /// CRITICAL FIX: Preserve existing episode status when updating episodes from RSS
    private func saveEpisodes(_ episodes: [Episode], for podcastID: UUID) async throws {
        try await dbManager.writeAsync { db in
            // For each episode, check if it exists and preserve its status
            for episode in episodes {
                // Check if episode already exists in database
                let existingEpisode = try Episode.fetchOne(db, key: episode.id)
                
                if let existing = existingEpisode {
                    // Episode exists - preserve user status and update other fields
                    var updatedEpisode = episode
                    updatedEpisode.status = existing.status // Preserve user's status changes
                    updatedEpisode.played = existing.played // Preserve legacy played field too
                    updatedEpisode.playbackPosition = existing.playbackPosition // Preserve playback position
                    
                    // Update the existing episode
                    try updatedEpisode.update(db)
                } else {
                    // New episode - save with default status
                    var newEpisode = episode
                    newEpisode.podcastID = podcastID // Ensure podcastID is set
                    try newEpisode.save(db)
                }
            }
            
            // Clean up episodes that no longer exist in the RSS feed
            // Get all current episode IDs from RSS
            let rssEpisodeIDs = Set(episodes.map { $0.id.uuidString })
            
            // Find episodes in database that are not in RSS feed
            if !rssEpisodeIDs.isEmpty {
                // Find orphaned episodes that are no longer in the RSS feed
                let orphanedEpisodes = try Episode
                    .filter(Column("podcastID") == podcastID)
                    .filter(!rssEpisodeIDs.contains(Column("id")))
                    .fetchAll(db)
                
                // Only delete episodes that are truly orphaned (not in RSS feed)
                // But preserve episodes with user interactions (played, queued)
                for episode in orphanedEpisodes {
                    // Only delete if episode has no user interactions
                    if episode.status.isEmpty && !episode.played && episode.playbackPosition == 0 {
                        try episode.delete(db)
                    }
                }
            }
        }
        
        // Clear memory cache for this podcast to force refresh
        cacheStore.clearEpisodePages(for: podcastID)
    }
    
    /// Add playback states to episodes
    private func addPlaybackStates(to episodes: [Episode]) async throws -> [EpisodeWithPlaybackState] {
        return try await dbManager.readAsync { db in
            episodes.map { episode in
                // Fetch actual playback state from database
                // CRITICAL FIX: PlaybackState stores episodeID as string, so convert UUID to string
                let playbackState = (try? PlaybackState.fetchOne(db, key: episode.id.uuidString)) ?? PlaybackState(
                    episodeID: episode.id,
                    position: 0.0,
                    finished: false
                )
                
                return EpisodeWithPlaybackState(
                    episode: episode,
                    playbackState: playbackState
                )
            }
        }
    }

    // MARK: - EpisodeRepositoryProtocol Implementation
    
    func fetchEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] {
        let (episodes, _) = try await fetchPage(podcastID: podcastID, cursor: nil, limit: 1000, ignoreCache: ignoreCache)
        return episodes
    }
    
    func fetchAllEpisodes(for podcastID: UUID, ignoreCache: Bool) async throws -> [EpisodeWithPlaybackState] {
        return try await fetchEpisodes(for: podcastID, ignoreCache: ignoreCache)
    }
    
    /// Fetch a single episode by ID with its playback state
    func fetchEpisode(by episodeID: UUID) async throws -> EpisodeWithPlaybackState? {
        return try await dbManager.readAsync { db in
            // CRITICAL FIX: Episodes are stored with UUID as string, so we need to convert
            guard let episode = try Episode.fetchOne(db, key: episodeID.uuidString) else {
                return nil
            }
            
            // Fetch playback state for this episode
            // CRITICAL FIX: PlaybackState also stores episodeID as string, so convert UUID to string
            let playbackState = try PlaybackState.fetchOne(db, key: episodeID.uuidString) ?? PlaybackState(
                episodeID: episodeID,
                position: 0,
                finished: false
            )
            
            return EpisodeWithPlaybackState(episode: episode, playbackState: playbackState)
        }
    }
    
    func saveEpisodes(_ episodes: [EpisodeWithPlaybackState], for podcastID: UUID) async throws {
        let episodeModels = episodes.map { $0.episode }
        try await saveEpisodes(episodeModels, for: podcastID)
    }
    
    func isStale(podcastID: UUID) -> Bool {
        // Check if we have any cached data for this podcast
        let hasCache = cacheStore.hasEpisodePages(for: podcastID)
        
        if !hasCache {
            return true // No cache means stale
        }
        
        // For episodes, consider stale after 1 hour
        // This is a simplified check - in practice you'd check the last fetch time
        return false // Placeholder - implement proper staleness check
    }
    
    var episodeChangesPublisher: AnyPublisher<CleanEpisodeChanges, Never> {
        changesSubject.eraseToAnyPublisher()
    }
}

/// GRDB-based implementation of the show repository protocol with caching.
final class GRDBShowRepository: ShowRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "GRDBRepositories")
    private let dbManager: DatabaseManager
    private let cacheStore: MemoryCacheStore
    
    // Staleness intervals
    private let showStalenessInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    
    init(
        dbManager: DatabaseManager,
        cacheStore: MemoryCacheStore
    ) {
        self.dbManager = dbManager
        self.cacheStore = cacheStore
    }
    
    func fetchShow(from feedURL: URL, ignoreCache: Bool) async throws -> ShowMetadata {
        // 1. Check memory cache first
        if !ignoreCache, let cached = cacheStore.showCache[feedURL] {
            // Check staleness and refresh in background if needed
            if isStale(feedURL: feedURL) {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshShow(feedURL: feedURL)
                }
            }
            return cached
        }
        
        // 2. For shows, we don't have a separate database table yet
        // This would be implemented with a proper shows table
        
        // 3. Return empty metadata for now
        return ShowMetadata(
            title: nil,
            author: nil,
            description: nil,
            artworkURL: nil,
            language: nil,
            categories: []
        )
    }
    
    func isStale(feedURL: URL) -> Bool {
        // For now, always consider stale
        // In a real implementation, you'd check the last fetch time
        return true
    }
    
    private func refreshShow(feedURL: URL) async {
        // Background refresh implementation would go here
        Self.logger.debug("Background refresh for show \(feedURL) - not implemented yet")
    }
}

/// GRDB-based implementation of the playback state repository protocol.
final class GRDBPlaybackStateRepository: PlaybackStateRepositoryProtocol {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "GRDBRepositories")
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }
    
    func savePlaybackState(_ state: PlaybackState) async throws {
        try await dbManager.writeAsync { db in
            // Save the playback state
            try state.save(db)
            
            // CRITICAL FIX: Also update the Episode.playbackPosition field to keep them synchronized
            // This ensures UI shows correct progress even when PlaybackState isn't cached
            try db.execute(sql: """
                UPDATE episodes 
                SET playbackPosition = ? 
                WHERE id = ?
            """, arguments: [state.position, state.episodeID.uuidString])
        }
        
        let posFormatted = String(format: "%.1f", state.position)
        Self.logger.debug("Saved progress: \(posFormatted)s for episode \(state.episodeID)")
    }
    
    func savePlaybackStates(_ states: [PlaybackState]) async throws {
        try await dbManager.writeAsync { db in
            for state in states {
                // Save the playback state
                try state.save(db)
                
                // CRITICAL FIX: Also update the Episode.playbackPosition field to keep them synchronized
                try db.execute(sql: """
                    UPDATE episodes 
                    SET playbackPosition = ? 
                    WHERE id = ?
                """, arguments: [state.position, state.episodeID.uuidString])
            }
        }
        
        for state in states {
            let posFormatted = String(format: "%.1f", state.position)
            Self.logger.debug("Saved progress: \(posFormatted)s for episode \(state.episodeID)")
        }
    }
    
    func fetchPlaybackState(for episodeID: UUID) async throws -> PlaybackState? {
        try await dbManager.readAsync { db in
            // CRITICAL FIX: PlaybackState stores episodeID as string, so convert UUID to string
            try PlaybackState.fetchOne(db, key: episodeID.uuidString)
        }
    }
    
    func markFinished(episodeID: UUID) async throws {
        let state = PlaybackState(episodeID: episodeID, position: 0, finished: true)
        try await savePlaybackState(state)
    }
    
    func fetchQueuedEpisodes() async throws -> [EpisodeWithPlaybackState] {
        return try await dbManager.readAsync { db in
            // Get episodes with queue positions, ordered by position
            let sql = """
                SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt
                FROM episodes e
                JOIN playback_state ps ON e.id = ps.episodeID
                WHERE ps.queuePosition IS NOT NULL
                ORDER BY ps.queuePosition ASC
            """
            
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.compactMap { row in
                guard let episode = try? Episode(row: row) else { return nil }
                
                let playbackState = PlaybackState(
                    episodeID: episode.id,
                    position: row["position"] ?? 0.0,
                    finished: row["finished"] ?? false,
                    queuePosition: row["queuePosition"],
                    updatedAt: row["updatedAt"] ?? Date()
                )
                
                return EpisodeWithPlaybackState(episode: episode, playbackState: playbackState)
            }
        }
    }
    
    func addToQueue(episodeID: UUID, position: Int) async throws {
        try await dbManager.writeAsync { db in
            // Check if episode is already in queue
            let existingState = try PlaybackState.fetchOne(db, key: episodeID.uuidString)
            
            if let _ = existingState?.queuePosition {
                throw RepositoryError.episodeAlreadyInQueue
            }

            // --- CORRECTED UNIFIED QUEUE LOGIC ---
            
            // 1. Handle currently playing episode IF adding to position 1
            if position == 1 {
                if let currentPlayingState = try PlaybackState.fetchOne(db, sql: "SELECT * FROM playback_state WHERE queuePosition = 1") {
                    let episodeRow = try Row.fetchOne(db, sql: "SELECT duration FROM episodes WHERE id = ?", arguments: [currentPlayingState.episodeID])
                    let episodeDuration = episodeRow?["duration"] as? Double ?? 0.0
                    let isFinished = currentPlayingState.finished || (episodeDuration > 0 && currentPlayingState.position >= episodeDuration)

                    if isFinished {
                        // Finished: Remove from queue
                        var finishedState = currentPlayingState
                        finishedState.queuePosition = nil
                        finishedState.finished = true
                        try finishedState.save(db)
                    } else {
                        // Not Finished: Move ONLY the current episode to position 2
                        // Find the next available position starting from 2
                        var nextPosition = 2
                        while true {
                            let existingAtPosition = try PlaybackState.fetchOne(db, sql: "SELECT * FROM playback_state WHERE queuePosition = ?", arguments: [nextPosition])
                            if existingAtPosition == nil {
                                // Found an open position
                                var movedState = currentPlayingState
                                movedState.queuePosition = nextPosition
                                try movedState.save(db)
                                break
                            }
                            nextPosition += 1
                        }
                    }
                }
            } else {
                // 2. Handle insertions into the middle of the queue (for positions > 1)
                let maxPosition = try Int.fetchOne(db, sql: "SELECT MAX(queuePosition) FROM playback_state WHERE queuePosition IS NOT NULL") ?? 0
                if position <= maxPosition {
                    // CRITICAL: Only shift episodes at/after insertion point, NEVER position 1
                    try db.execute(sql: "UPDATE playback_state SET queuePosition = queuePosition + 1 WHERE queuePosition >= ? AND queuePosition > 1", arguments: [position])
                }
            }
            
            // 3. ALWAYS add the new episode at the specified position
            let newState = PlaybackState(
                episodeID: episodeID,
                position: existingState?.position ?? 0.0,
                finished: existingState?.finished ?? false,
                queuePosition: position,
                updatedAt: Date()
            )
            try newState.save(db)
        }
        
        // Notify that an episode was added to queue
        await MainActor.run {
            NotificationCenter.default.post(
                name: .episodeAddedToQueue,
                object: episodeID,
                userInfo: ["position": position]
            )
        }
    }
    
    func removeFromQueue(episodeID: UUID) async throws {
        try await dbManager.writeAsync { db in
            // Get the current queue position of the episode to remove
            // CRITICAL FIX: PlaybackState stores episodeID as string, so convert UUID to string
            guard let currentState = try PlaybackState.fetchOne(db, key: episodeID.uuidString),
                  let currentPosition = currentState.queuePosition else {
                return // Episode not in queue
            }
            
            // CRITICAL: Never allow removal of the currently playing episode (position 1)
            if currentPosition == 1 {
                // If trying to remove currently playing episode, just mark it as finished and remove from queue
                let updatedState = PlaybackState(
                    episodeID: episodeID,
                    position: currentState.position,
                    finished: true,
                    queuePosition: nil,
                    updatedAt: Date()
                )
                try updatedState.save(db)
                return // Don't shift anything
            }
            
            // Remove from queue by setting queuePosition to NULL
            let updatedState = PlaybackState(
                episodeID: episodeID,
                position: currentState.position,
                finished: currentState.finished,
                queuePosition: nil,
                updatedAt: Date()
            )
            try updatedState.save(db)
            
            // DEFINITIVE QUEUE LOGIC: Only shift episodes after the removed position
            // NEVER shift position 1 (currently playing episode)
            try db.execute(sql: """
                UPDATE playback_state 
                SET queuePosition = queuePosition - 1 
                WHERE queuePosition > ? AND queuePosition > 1 AND queuePosition IS NOT NULL
            """, arguments: [currentPosition])
        }
        
        // Notify that an episode was removed from queue
        await MainActor.run {
            NotificationCenter.default.post(
                name: .episodeRemovedFromQueue,
                object: episodeID
            )
        }
    }
    
    func moveInQueue(episodeID: UUID, toPosition: Int) async throws {
        try await dbManager.writeAsync { db in
            // CRITICAL FIX: PlaybackState stores episodeID as string, so convert UUID to string
            guard let currentState = try PlaybackState.fetchOne(db, key: episodeID.uuidString),
                  let currentPosition = currentState.queuePosition else {
                throw RepositoryError.notFound
            }
            
            if currentPosition == toPosition {
                return // Already at target position
            }
            
            // CRITICAL: Prevent moving TO position 1 unless it's already at position 1
            // Position 1 is reserved for currently playing episode
            if toPosition == 1 && currentPosition != 1 {
                throw RepositoryError.invalidOperation // Can't move non-playing episode to position 1
            }
            
            if currentPosition < toPosition {
                // Moving down: shift episodes between current and target up by 1
                // NEVER shift position 1 (currently playing episode)
                try db.execute(sql: """
                    UPDATE playback_state 
                    SET queuePosition = queuePosition - 1 
                    WHERE queuePosition > ? AND queuePosition <= ? AND queuePosition > 1 AND queuePosition IS NOT NULL
                """, arguments: [currentPosition, toPosition])
            } else {
                // Moving up: shift episodes between target and current down by 1
                // NEVER shift position 1 (currently playing episode)
                try db.execute(sql: """
                    UPDATE playback_state 
                    SET queuePosition = queuePosition + 1 
                    WHERE queuePosition >= ? AND queuePosition < ? AND queuePosition > 1 AND queuePosition IS NOT NULL
                """, arguments: [toPosition, currentPosition])
            }
            
            // Update the episode to new position
            let updatedState = PlaybackState(
                episodeID: episodeID,
                position: currentState.position,
                finished: currentState.finished,
                queuePosition: toPosition,
                updatedAt: Date()
            )
            try updatedState.save(db)
        }
        
        // Notify that the queue order changed
        await MainActor.run {
            NotificationCenter.default.post(
                name: .queueOrderChanged,
                object: episodeID,
                userInfo: ["newPosition": toPosition]
            )
        }
    }
    
    func fetchAllPlaybackStates() async throws -> [PlaybackState] {
        try await dbManager.readAsync { db in
            try PlaybackState.fetchAll(db)
        }
    }
    
    func getNextQueuedEpisode() async throws -> EpisodeWithPlaybackState? {
        return try await dbManager.readAsync { db in
            let sql = """
                SELECT e.*, ps.position, ps.finished, ps.queuePosition, ps.updatedAt
                FROM episodes e
                JOIN playback_state ps ON e.id = ps.episodeID
                WHERE ps.queuePosition = 1
                LIMIT 1
            """
            
            guard let row = try Row.fetchOne(db, sql: sql),
                  let episode = try? Episode(row: row) else {
                return nil
            }
            
            let playbackState = PlaybackState(
                episodeID: episode.id,
                position: row["position"] ?? 0.0,
                finished: row["finished"] ?? false,
                queuePosition: row["queuePosition"],
                updatedAt: row["updatedAt"] ?? Date()
            )
            
            return EpisodeWithPlaybackState(episode: episode, playbackState: playbackState)
        }
    }
    
    func getMaxQueuePosition() async throws -> Int? {
        try await dbManager.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT MAX(queuePosition) FROM playback_state WHERE queuePosition IS NOT NULL")
        }
    }

    func reorderQueue(episodeIDs: [UUID]) async throws {
        try await dbManager.writeAsync { db in
            // Clear all queue positions first
            try db.execute(sql: """
                UPDATE playback_state SET queuePosition = NULL WHERE queuePosition IS NOT NULL
            """)

            // Set new positions based on the order of episodeIDs
            for (index, episodeID) in episodeIDs.enumerated() {
                let position = index + 1
                let idString = episodeID.uuidString

                // Check if a playback_state row exists for this episode
                let exists = try PlaybackState.fetchOne(db, key: idString) != nil

                if exists {
                    try db.execute(sql: """
                        UPDATE playback_state SET queuePosition = ?, updatedAt = ? WHERE episodeID = ?
                    """, arguments: [position, Date(), idString])
                } else {
                    // Create a new playback_state entry for this episode
                    let state = PlaybackState(
                        episodeID: episodeID,
                        position: 0.0,
                        finished: false,
                        queuePosition: position,
                        updatedAt: Date()
                    )
                    try state.save(db)
                }
            }
        }

        // Notify that the queue order changed
        await MainActor.run {
            NotificationCenter.default.post(name: .queueOrderChanged, object: nil)
        }
    }
}

// MARK: - Supporting Types

// PodcastRepositoryError is defined in RepositoryProtocols.swift



// MARK: - Repository Errors

enum EpisodeRepositoryError: Error, LocalizedError {
    case podcastNotFound
    case networkError(Error)
    case parseError(Error)
    case databaseError(Error)
    
    var errorDescription: String? {
        switch self {
        case .podcastNotFound:
            return "Podcast not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parseError(let error):
            return "Parse error: \(error.localizedDescription)"
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
}
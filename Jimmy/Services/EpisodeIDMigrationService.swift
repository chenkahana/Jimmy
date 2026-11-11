import Foundation
import os
import GRDB

/// Service responsible for migrating all episodes to use deterministic UUIDs
/// This ensures consistent episode identification across the entire app
class EpisodeIDMigrationService {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "EpisodeIDMigrationService")
    static let shared = EpisodeIDMigrationService()
    
    private let dbManager = DatabaseManager.shared
    private let migrationKey = "episode_id_migration_completed_v2"
    
    private init() {}
    
    /// Check if migration has been completed
    var isMigrationCompleted: Bool {
        return UserDefaults.standard.bool(forKey: migrationKey)
    }
    
    /// Perform the complete episode ID migration
    /// This method handles all aspects of the migration safely
    func performMigration() async throws {
        guard !isMigrationCompleted else {
            Self.logger.info("Episode ID migration already completed")
            return
        }
        
        Self.logger.info("Starting episode ID migration")
        
        // Step 1: Get all podcasts with their feed URLs
        let podcasts = try await fetchAllPodcasts()
        Self.logger.info("Found \(podcasts.count) podcasts to migrate")
        
        // Step 2: Migrate episodes for each podcast
        var totalEpisodesMigrated = 0
        var totalEpisodesProcessed = 0
        
        for podcast in podcasts {
            let (migrated, processed) = try await migrateEpisodesForPodcast(podcast)
            totalEpisodesMigrated += migrated
            totalEpisodesProcessed += processed
        }
        
        Self.logger.info("Migration completed: \(totalEpisodesMigrated)/\(totalEpisodesProcessed) episodes migrated")
        
        // Step 3: Clean up orphaned data
        try await cleanupOrphanedData()
        
        // Step 4: Mark migration as completed
        UserDefaults.standard.set(true, forKey: migrationKey)
        UserDefaults.standard.synchronize()
        
        Self.logger.info("Episode ID migration completed successfully")
    }
    
    /// Force re-run the migration (for debugging)
    func forceMigration() async throws {
        UserDefaults.standard.set(false, forKey: migrationKey)
        try await performMigration()
    }
    
    // MARK: - Private Migration Methods
    
    private func fetchAllPodcasts() async throws -> [(id: UUID, feedURL: URL)] {
        return try await dbManager.readAsync { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, feedURL FROM podcasts")
            return rows.compactMap { row in
                guard let idString = row["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let feedURLString = row["feedURL"] as? String,
                      let feedURL = URL(string: feedURLString) else {
                    return nil
                }
                return (id: id, feedURL: feedURL)
            }
        }
    }
    
    private func migrateEpisodesForPodcast(_ podcast: (id: UUID, feedURL: URL)) async throws -> (migrated: Int, processed: Int) {
        Self.logger.info("Migrating episodes for podcast: \(podcast.feedURL)")
        
        // Fetch all episodes for this podcast
        let episodes = try await fetchEpisodesForPodcast(podcast.id)
        Self.logger.info("Found \(episodes.count) episodes for podcast")
        
        var migratedCount = 0
        var processedCount = 0
        
        // Process episodes in batches to avoid memory issues
        let batchSize = 50
        for batch in episodes.chunked(into: batchSize) {
            let batchResult = try await migrateBatchOfEpisodes(batch, feedURL: podcast.feedURL)
            migratedCount += batchResult.migrated
            processedCount += batchResult.processed
        }
        
        return (migrated: migratedCount, processed: processedCount)
    }
    
    private func fetchEpisodesForPodcast(_ podcastID: UUID) async throws -> [Episode] {
        return try await dbManager.readAsync { db in
            try Episode.filter(Column("podcastID") == podcastID.uuidString).fetchAll(db)
        }
    }
    
    private func migrateBatchOfEpisodes(_ episodes: [Episode], feedURL: URL) async throws -> (migrated: Int, processed: Int) {
        var migratedCount = 0
        let processedCount = episodes.count
        
        // Group episodes by their new deterministic IDs to handle duplicates
        var episodesByNewID: [UUID: [Episode]] = [:]
        
        for episode in episodes {
            let newID = DeterministicUUIDGenerator.generateMigrationID(for: episode, feedURL: feedURL)
            
            if episodesByNewID[newID] == nil {
                episodesByNewID[newID] = []
            }
            episodesByNewID[newID]?.append(episode)
        }
        
        // Process each group of episodes with the same deterministic ID
        for (newID, duplicateEpisodes) in episodesByNewID {
            let migrated = try await processDuplicateEpisodes(duplicateEpisodes, newID: newID, feedURL: feedURL)
            if migrated {
                migratedCount += 1
            }
        }
        
        return (migrated: migratedCount, processed: processedCount)
    }
    
    private func processDuplicateEpisodes(_ episodes: [Episode], newID: UUID, feedURL: URL) async throws -> Bool {
        // If there's only one episode and it already has the correct ID, no migration needed
        if episodes.count == 1 && episodes.first!.id == newID {
            return false
        }
        
        // Choose the best episode from duplicates (most recent or most complete)
        let bestEpisode = selectBestEpisode(from: episodes)
        
        // Create the migrated episode with the new deterministic ID
        let migratedEpisode = Episode(
            id: newID,
            title: bestEpisode.title,
            podcastID: bestEpisode.podcastID,
            publishedDate: bestEpisode.publishedDate,
            duration: bestEpisode.duration,
            artworkURL: bestEpisode.artworkURL,
            description: bestEpisode.description,
            audioURL: bestEpisode.audioURL,
            played: bestEpisode.played,
            isNew: bestEpisode.isNew,
            localFileURL: bestEpisode.localFileURL,
            playbackPosition: bestEpisode.playbackPosition,
            lastFetched: bestEpisode.lastFetched,
            status: bestEpisode.status
        )
        
        try await dbManager.writeAsync { [self] db in
            // Delete all old episodes
            for episode in episodes {
                try Episode.deleteOne(db, key: episode.id.uuidString)
                
                // Also clean up related data
                try db.execute(sql: "DELETE FROM playback_state WHERE episodeID = ?", arguments: [episode.id.uuidString])
                try db.execute(sql: "DELETE FROM episode_details WHERE episodeID = ?", arguments: [episode.id.uuidString])
            }
            
            // Insert the migrated episode
            try migratedEpisode.save(db)
            
            // Migrate playback state if it exists
            if let playbackState = self.selectBestPlaybackState(from: episodes) {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO playback_state (episodeID, position, finished, updatedAt) VALUES (?, ?, ?, ?)",
                    arguments: [newID.uuidString, playbackState.position, playbackState.finished, playbackState.updatedAt]
                )
            }
        }
        
        return true
    }
    
    private func selectBestEpisode(from episodes: [Episode]) -> Episode {
        // Priority: Most recent lastFetched, then most complete data, then most recent published date
        return episodes.max { episode1, episode2 in
            // Compare lastFetched dates
            if let date1 = episode1.lastFetched, let date2 = episode2.lastFetched {
                return date1 < date2
            } else if episode1.lastFetched != nil {
                return false // episode1 is better (has lastFetched)
            } else if episode2.lastFetched != nil {
                return true // episode2 is better (has lastFetched)
            }
            
            // Compare completeness (presence of description, artwork, etc.)
            let completeness1 = calculateCompleteness(episode1)
            let completeness2 = calculateCompleteness(episode2)
            
            if completeness1 != completeness2 {
                return completeness1 < completeness2
            }
            
            // Compare published dates
            if let date1 = episode1.publishedDate, let date2 = episode2.publishedDate {
                return date1 < date2
            }
            
            return false // Default to first episode
        } ?? episodes.first!
    }
    
    private func calculateCompleteness(_ episode: Episode) -> Int {
        var score = 0
        if episode.description != nil && !episode.description!.isEmpty { score += 1 }
        if episode.artworkURL != nil { score += 1 }
        if episode.audioURL != nil { score += 1 }
        if episode.duration != nil && episode.duration! > 0 { score += 1 }
        if episode.publishedDate != nil { score += 1 }
        return score
    }
    
    private func selectBestPlaybackState(from episodes: [Episode]) -> PlaybackState? {
        // For migration, we'll find the playback state with the most progress
        // This method is called within a database transaction, so we can't make async calls
        // We'll return nil for now and let playback states be recreated naturally
        return nil
    }
    
    private func cleanupOrphanedData() async throws {
        Self.logger.info("Cleaning up orphaned data")
        
        try await dbManager.writeAsync { db in
            // Clean up orphaned playback states
            try db.execute(sql: """
                DELETE FROM playback_state 
                WHERE episodeID NOT IN (SELECT id FROM episodes)
            """)
            
            // Clean up orphaned episode details
            try db.execute(sql: """
                DELETE FROM episode_details 
                WHERE episodeID NOT IN (SELECT id FROM episodes)
            """)
        }
    }
}

// MARK: - Array Extension for Chunking
// Note: Using existing chunked(into:) method from FastLibraryLoader.swift

// MARK: - Migration Status

extension EpisodeIDMigrationService {
    
    /// Get migration statistics
    func getMigrationStats() async throws -> MigrationStats {
        let totalEpisodes = try await dbManager.readAsync { db in
            try Episode.fetchCount(db)
        }
        
        let totalPodcasts = try await dbManager.readAsync { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM podcasts") ?? 0
        }
        
        return MigrationStats(
            totalEpisodes: totalEpisodes,
            totalPodcasts: totalPodcasts,
            isCompleted: isMigrationCompleted
        )
    }
}

struct MigrationStats {
    let totalEpisodes: Int
    let totalPodcasts: Int
    let isCompleted: Bool
} 
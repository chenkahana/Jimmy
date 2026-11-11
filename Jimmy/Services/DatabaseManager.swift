import Foundation
import GRDB
import os

/// Database health status for diagnostics
struct DatabaseHealthStatus {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DatabaseHealthStatus")
    let isReady: Bool
    let isAccessible: Bool
    let podcastCount: Int
    let hasRequiredTables: Bool
    let tableNames: [String]
    let error: String?
    
    init(isReady: Bool, isAccessible: Bool, podcastCount: Int, hasRequiredTables: Bool, tableNames: [String], error: String? = nil) {
        self.isReady = isReady
        self.isAccessible = isAccessible
        self.podcastCount = podcastCount
        self.hasRequiredTables = hasRequiredTables
        self.tableNames = tableNames
        self.error = error
    }
}

/// DatabaseManager handles the SQLite database setup and provides access to the database pool
/// for GRDB operations. It ensures proper database initialization, migrations, and thread safety.
/// 
/// CRITICAL FIX: Made initialization asynchronous to prevent main thread blocking
class DatabaseManager {
    static let shared = DatabaseManager()
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "DatabaseManager")

    /// The database pool for concurrent database access.
    private var dbPool: DatabasePool?
    
    /// The path to the database file in the app's Documents directory
    private let dbPath: String
    
    /// Indicates if the database is ready for use
    @Published private(set) var isReady = false
    
    /// Private initializer to enforce singleton pattern
    /// CRITICAL FIX: No longer performs heavy operations synchronously
    private init() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
        }
        let databasePath = documentsPath.appendingPathComponent("jimmy.db").path
        
        // Initialize dbPath property
        self.dbPath = databasePath
        
        // Initialize database asynchronously to prevent main thread blocking
        Task.detached(priority: .utility) { [weak self] in
            await self?.initializeDatabase()
        }
    }

    /// Test-only initializer: creates an isolated database at `path` and runs all
    /// migrations synchronously before returning, so characterization tests can get a
    /// ready-to-use instance without touching the app's real `.shared` database.
    /// Not used by the app itself.
    init(path: String) async throws {
        self.dbPath = path
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        dbPool = try DatabasePool(path: path, configuration: config)
        try await runMigrations()
        isReady = true
    }

    /// Initialize database asynchronously to prevent main thread blocking
    private func initializeDatabase() async {
        do {
            // Create database pool with optimized configuration
            var config = Configuration()
            
            // PERF-03: Connection limits and timeout handling
            config.maximumReaderCount = 4  // Limit concurrent readers to prevent resource exhaustion
            config.busyMode = .timeout(5.0)  // 5 second timeout for busy database
            
            config.prepareDatabase { db in
                // Enable foreign keys for data integrity
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                
                // Try WAL mode first, fallback to DELETE mode if it fails
                // WAL mode enables better concurrency (multiple readers + single writer)
                do {
                    try db.execute(sql: "PRAGMA journal_mode = WAL")
                } catch {
                    try db.execute(sql: "PRAGMA journal_mode = DELETE")
                }
                
                // Optimize for podcast app use case
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                
                // Enable GRDB trace logging for debugging FK issues
                #if DEBUG
                // db.trace { print("SQL: \($0)") }
                #endif
            }
            
            dbPool = try DatabasePool(path: dbPath, configuration: config)
            
            // Run migrations to create and update schema
            try await runMigrations()
            
            await MainActor.run {
                self.isReady = true
            }
            
        } catch {
            
            // Try fallback initialization
            await handleDatabaseInitializationFailure(error)
        }
    }
    
    /// Handle database initialization failure with fallback
    private func handleDatabaseInitializationFailure(_ error: Error) async {
        
        do {
            // Fallback to in-memory database in case of failure
            // This ensures the app won't crash, but data won't persist
            var fallbackConfig = Configuration()
            fallbackConfig.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                // Use simple DELETE journal mode for in-memory database (WAL not supported)
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                // Fallback SQL tracing disabled
                // #if DEBUG
                // db.trace { print("FALLBACK SQL: \($0)") }
                // #endif
            }
            
            let fallbackPool = try DatabasePool(path: ":memory:", configuration: fallbackConfig)
            
            self.dbPool = fallbackPool
            
            try await runMigrations()
            
            await MainActor.run {
                self.isReady = true
            }
            
        } catch {
            // Create a minimal working database pool with no configuration
            do {
                // Create the most basic database possible with proper configuration
                var bareMinimumConfig = Configuration()
                bareMinimumConfig.prepareDatabase { db in
                    // Use DELETE journal mode for in-memory database (WAL not supported)
                    try db.execute(sql: "PRAGMA journal_mode = DELETE")
                }
                
                self.dbPool = try DatabasePool(path: ":memory:", configuration: bareMinimumConfig)
                await MainActor.run {
                    self.isReady = true
                }
            } catch {
                // This should never happen, but if it does, we'll create a nil pool
                // and handle it gracefully in getPool()
                await MainActor.run {
                    self.isReady = true
                }
            }
        }
    }
    
    /// Wait for database to be ready (non-blocking)
    func waitForReady() async {
        while !isReady {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    /// Get the database pool, waiting for initialization if needed
    private func getPool() async throws -> DatabasePool {
        await waitForReady()
        guard let pool = dbPool else {
            // If we still don't have a pool, create an emergency one
            
            // Use proper configuration for in-memory database
            var emergencyConfig = Configuration()
            emergencyConfig.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                // Use DELETE journal mode for in-memory database (WAL not supported)
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            
            let emergencyPool = try DatabasePool(path: ":memory:", configuration: emergencyConfig)
            self.dbPool = emergencyPool
            return emergencyPool
        }
        return pool
    }

    /// Run database migrations to set up and update schema
    private func runMigrations() async throws {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            // Create podcasts table with all required columns (matching createTables)
            try db.create(table: "podcasts", ifNotExists: true) { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("title", .text).notNull()
                t.column("author", .text).notNull()
                t.column("description", .text)
                t.column("feedURL", .text).notNull().unique()
                t.column("artworkURL", .text)
                t.column("autoAddToQueue", .boolean).notNull().defaults(to: false)
                t.column("notificationsEnabled", .boolean).notNull().defaults(to: false)
                t.column("lastEpisodeDate", .datetime)
                t.column("etag", .text)
                t.column("lastFetched", .datetime)
                t.column("cleanTitle", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            
            // Assertion to ensure primary key is TEXT for UUIDs
            let podcastColumns = try db.columns(in: "podcasts")
            if let idColumn = podcastColumns.first(where: { $0.name == "id" }) {
                if idColumn.type.uppercased() != "TEXT" {
                    Self.logger.warning("Podcast 'id' primary key should be TEXT, found: \(idColumn.type)")
                    // Don't crash, just log the warning
                }
            } else {
                Self.logger.warning("Could not find 'id' column in 'podcasts' table")
                // Don't crash, the table might be created differently
            }
            
            // Create episodes table with all required columns (matching createTables)
            try db.create(table: "episodes", ifNotExists: true) { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("podcastID", .text).notNull().indexed()
                    .references("podcasts", column: "id", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("audioURL", .text)
                t.column("publishedDate", .datetime)
                t.column("duration", .double)
                t.column("artworkURL", .text)
                t.column("description", .text)
                t.column("played", .boolean).defaults(to: false)
                t.column("isNew", .boolean).defaults(to: true)
                t.column("localFileURL", .text)
                t.column("playbackPosition", .double).defaults(to: 0.0)
                t.column("page", .integer).notNull().defaults(to: 1)
                t.column("fetchedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
        
        migrator.registerMigration("v2_add_caching_tables") { db in
            // v1 now includes all podcast columns, so we only need to create additional tables
            
            // Create shows table
            try db.create(table: "shows", ifNotExists: true) { t in
                t.column("feedURL", .text).primaryKey()
                t.column("showDescription", .text).notNull()
                t.column("author", .text).notNull()
                t.column("language", .text).notNull()
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            
            // Create episode_details table
            try db.create(table: "episode_details", ifNotExists: true) { t in
                t.column("episodeID", .text).primaryKey()
                    .references("episodes", column: "id", onDelete: .cascade)
                t.column("fullDescription", .text).notNull()
                t.column("chaptersJSON", .text)
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            
            // Create playback_state table
            try db.create(table: "playback_state", ifNotExists: true) { t in
                t.column("episodeID", .text).primaryKey()
                    .references("episodes", column: "id", onDelete: .cascade)
                t.column("position", .double).notNull().defaults(to: 0.0)
                t.column("finished", .boolean).notNull().defaults(to: false)
                t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
        
        migrator.registerMigration("v3_fix_schema_mismatch") { db in
            // v1 now includes all required columns, so this migration is no longer needed
            // Keeping this as a no-op to maintain migration history
        }
        
        migrator.registerMigration("v4_add_clean_title") { db in
            // v1 now includes cleanTitle column, so this migration is no longer needed
            // Keeping this as a no-op to maintain migration history
        }
        
        migrator.registerMigration("v5_ensure_all_columns") { db in
            // This migration ensures all columns exist for databases created with old v1
            // Check podcasts table for missing columns
            let podcastColumns = try db.columns(in: "podcasts").map(\.name)
            
            if !podcastColumns.contains("etag") {
                try db.alter(table: "podcasts") { t in
                    t.add(column: "etag", .text)
                }
            }
            
            if !podcastColumns.contains("lastFetched") {
                try db.alter(table: "podcasts") { t in
                    t.add(column: "lastFetched", .datetime)
                }
            }
            
            if !podcastColumns.contains("cleanTitle") {
                try db.alter(table: "podcasts") { t in
                    t.add(column: "cleanTitle", .text).notNull().defaults(to: "")
                }
                
                // Populate cleanTitle for existing podcasts
                let existingPodcasts = try Row.fetchAll(db, sql: "SELECT id, title FROM podcasts")
                
                for row in existingPodcasts {
                    // Handle UUID that might be stored as Data or String
                    let id: String
                    if let uuidData = row["id"] as? Data {
                        // UUID stored as binary data (16 bytes)
                        let uuid = UUID(uuid: uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) })
                        id = uuid.uuidString
                    } else if let uuidString = row["id"] as? String {
                        // UUID stored as string
                        id = uuidString
                    } else {
                        // Skip this row if we can't parse the ID
                        continue
                    }
                    
                    let title: String = row["title"]
                    let cleanTitle = Podcast.processCleanTitle(from: title)
                    
                    try db.execute(
                        sql: "UPDATE podcasts SET cleanTitle = ? WHERE id = ?",
                        arguments: [cleanTitle, id]
                    )
                }
            }
            
            // Check episodes table for missing columns
            let episodeColumns = try db.columns(in: "episodes").map(\.name)
            
            if !episodeColumns.contains("artworkURL") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "artworkURL", .text)
                }
            }
            
            if !episodeColumns.contains("description") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "description", .text)
                }
            }
            
            if !episodeColumns.contains("page") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "page", .integer).notNull().defaults(to: 1)
                }
            }
            
            if !episodeColumns.contains("fetchedAt") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "fetchedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                }
            }
            
            // Add lastFetched column to episodes table to fix SQL error
            if !episodeColumns.contains("lastFetched") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "lastFetched", .datetime)
                }
            }
        }
        
        migrator.registerMigration("v7_fix_clean_titles") { db in
            // Fix corrupted cleanTitle values by regenerating them from the original title
            let existingPodcasts = try Row.fetchAll(db, sql: "SELECT id, title, cleanTitle FROM podcasts")
            
            for row in existingPodcasts {
                let id = row["id"] as String
                let title = row["title"] as String
                let currentCleanTitle = row["cleanTitle"] as String
                
                // Regenerate cleanTitle using the same logic as the Podcast model
                let newCleanTitle = Podcast.processCleanTitle(from: title)
                
                // Only update if the cleanTitle has changed
                if newCleanTitle != currentCleanTitle {
                    try db.execute(sql: "UPDATE podcasts SET cleanTitle = ? WHERE id = ?", arguments: [newCleanTitle, id])
                }
            }
        }
        
        migrator.registerMigration("v6_fix_episode_schema") { db in
            // Additional migration to ensure episodes table has all required columns
            // This fixes the "table episodes has no column named lastFetched" error
            let episodeColumns = try db.columns(in: "episodes").map(\.name)
            
            // Ensure all Episode model fields have corresponding database columns
            let requiredColumns = [
                ("id", "text", true),
                ("podcastID", "text", false),
                ("title", "text", true),
                ("audioURL", "text", false),
                ("publishedDate", "datetime", false),
                ("duration", "double", false),
                ("artworkURL", "text", false),
                ("description", "text", false),
                ("played", "boolean", false),
                ("isNew", "boolean", false),
                ("localFileURL", "text", false),
                ("playbackPosition", "double", false),
                ("lastFetched", "datetime", false),
                ("fetchedAt", "datetime", false),
                ("page", "integer", false)
            ]
            
            for (columnName, columnType, isRequired) in requiredColumns {
                if !episodeColumns.contains(columnName) {
                    switch columnType {
                    case "text":
                        if isRequired {
                            try db.alter(table: "episodes") { t in
                                t.add(column: columnName, .text).notNull().defaults(to: "")
                            }
                        } else {
                            try db.alter(table: "episodes") { t in
                                t.add(column: columnName, .text)
                            }
                        }
                    case "datetime":
                        try db.alter(table: "episodes") { t in
                            t.add(column: columnName, .datetime)
                        }
                    case "double":
                        try db.alter(table: "episodes") { t in
                            t.add(column: columnName, .double).defaults(to: 0.0)
                        }
                    case "boolean":
                        try db.alter(table: "episodes") { t in
                            t.add(column: columnName, .boolean).defaults(to: false)
                        }
                    case "integer":
                        try db.alter(table: "episodes") { t in
                            t.add(column: columnName, .integer).defaults(to: 1)
                        }
                    default:
                        break
                    }
                }
            }
        }
        
        migrator.registerMigration("v8_fix_episode_fk_constraints") { db in
            // Fix FK constraints and NOT NULL constraint on episodes.podcastID
            // This migration addresses the core issue where episodes have nil podcastID
            // and FK constraints don't properly cascade delete
            
            // First, clean up any episodes with nil podcastID that reference non-existent podcasts
            try db.execute(sql: """
                DELETE FROM episodes 
                WHERE podcastID IS NULL 
                OR podcastID NOT IN (SELECT id FROM podcasts)
            """)
            
            // SQLite doesn't support modifying constraints directly, so we need to recreate the table
            // Create new episodes table with proper constraints
            try db.create(table: "episodes_new") { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("podcastID", .text).notNull().indexed()
                    .references("podcasts", column: "id", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("audioURL", .text)
                t.column("publishedDate", .datetime)
                t.column("duration", .double)
                t.column("artworkURL", .text)
                t.column("description", .text)
                t.column("played", .boolean).defaults(to: false)
                t.column("isNew", .boolean).defaults(to: true)
                t.column("localFileURL", .text)
                t.column("playbackPosition", .double).defaults(to: 0.0)
                t.column("lastFetched", .datetime)
                t.column("fetchedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.column("page", .integer).notNull().defaults(to: 1)
            }
            
            // Copy valid data from old table to new table
            try db.execute(sql: """
                INSERT INTO episodes_new 
                SELECT id, podcastID, title, audioURL, publishedDate, duration, 
                       artworkURL, description, played, isNew, localFileURL, 
                       playbackPosition, lastFetched, fetchedAt, page
                FROM episodes 
                WHERE podcastID IS NOT NULL
            """)
            
            // Drop old table and rename new table
            try db.drop(table: "episodes")
            try db.rename(table: "episodes_new", to: "episodes")
            
            // Add composite index for better performance
            try db.create(index: "idx_episodes_podcast_id", on: "episodes", columns: ["podcastID", "id"])
        }
        
        migrator.registerMigration("v9_add_library_cache_table") { db in
            // Create library_cache table for WorldClassIntegration persistence
            // Stores showOrder and latestEpisodeByShow for sub-50ms cold-launch performance
            try db.create(table: "library_cache", ifNotExists: true) { t in
                t.column("key", .text).primaryKey().notNull()
                t.column("value", .text).notNull()
                t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
        
        migrator.registerMigration("v10_add_episode_status") { db in
            // Add status column to episodes table for episode status indicators
            try db.alter(table: "episodes") { t in
                t.add(column: "status", .integer).notNull().defaults(to: 0)
            }
        }
        
        migrator.registerMigration("v11_add_library_sort_table") { db in
            // Create library_sort table for Phase A - Sorting & Caching Plan
            // Stores showOrder and latestDateByShow for sub-250ms cold-launch performance
            try db.create(table: "library_sort", ifNotExists: true) { t in
                t.column("showID", .text).primaryKey()
                t.column("latestDate", .integer)     // Unix epoch
                t.column("position", .integer)       // 0-based in showOrder
            }
        }
        
        migrator.registerMigration("v12_fix_hebrew_titles") { db in
            // Fix corrupted Hebrew episode and podcast titles by re-processing them with proper HTML entity decoding
            Self.logger.info("Starting Hebrew title repair migration")
            
            // Helper function to decode HTML entities (same as in ConcreteRSSParser)
            func decodeHTMLEntities(_ text: String) -> String {
                var result = text
                
                // Decode common HTML entities
                let htmlEntities = [
                    "&amp;": "&",
                    "&lt;": "<",
                    "&gt;": ">",
                    "&quot;": "\"",
                    "&apos;": "'",
                    "&nbsp;": " ",
                    "&#39;": "'",
                    "&#x27;": "'",
                    "&rsquo;": "'",
                    "&lsquo;": "'",
                    "&rdquo;": "\u{201D}",
                    "&ldquo;": "\u{201C}",
                    "&mdash;": "—",
                    "&ndash;": "–",
                    "&hellip;": "…",
                    "&#8211;": "–",
                    "&#8212;": "—",
                    "&#8216;": "'",
                    "&#8217;": "'",
                    "&#8220;": "\u{201C}",
                    "&#8221;": "\u{201D}",
                    "&#8230;": "…"
                ]
                
                for (entity, replacement) in htmlEntities {
                    result = result.replacingOccurrences(of: entity, with: replacement)
                }
                
                // Handle numeric HTML entities (&#123;) - crucial for Hebrew characters
                let numericEntityPattern = "&#(\\d+);"
                if let regex = try? NSRegularExpression(pattern: numericEntityPattern, options: []) {
                    let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
                    
                    // Process matches in reverse order to avoid index shifting
                    for match in matches.reversed() {
                        guard let numberRange = Range(match.range(at: 1), in: result),
                              let number = Int(String(result[numberRange])),
                              let scalar = UnicodeScalar(number),
                              let fullRange = Range(match.range, in: result) else {
                            continue
                        }
                        result.replaceSubrange(fullRange, with: String(scalar))
                    }
                }
                
                // Handle hex HTML entities (&#x123;) - also important for Hebrew
                let hexEntityPattern = "&#x([0-9a-fA-F]+);"
                if let regex = try? NSRegularExpression(pattern: hexEntityPattern, options: []) {
                    let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.count))
                    
                    // Process matches in reverse order to avoid index shifting
                    for match in matches.reversed() {
                        guard let numberRange = Range(match.range(at: 1), in: result),
                              let number = Int(String(result[numberRange]), radix: 16),
                              let scalar = UnicodeScalar(number),
                              let fullRange = Range(match.range, in: result) else {
                            continue
                        }
                        result.replaceSubrange(fullRange, with: String(scalar))
                    }
                }
                
                return result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Helper function to check if text contains Hebrew characters
            func containsHebrew(_ text: String) -> Bool {
                return text.unicodeScalars.contains { scalar in
                    return (0x0590...0x05FF).contains(scalar.value) // Hebrew Unicode block
                }
            }
            
            // Fix podcast titles
            let podcasts = try Row.fetchAll(db, sql: "SELECT id, title FROM podcasts")
            var podcastsFixed = 0
            
            for row in podcasts {
                let id = row["id"] as String
                let originalTitle = row["title"] as String
                
                // Check if title might be corrupted (contains HTML entities or is suspiciously empty for Hebrew podcasts)
                if originalTitle.contains("&#") || originalTitle.contains("&") || originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let decodedTitle = decodeHTMLEntities(originalTitle)
                    
                    if decodedTitle != originalTitle && !decodedTitle.isEmpty {
                        try db.execute(sql: "UPDATE podcasts SET title = ? WHERE id = ?", arguments: [decodedTitle, id])
                        podcastsFixed += 1
                    }
                }
            }
            
            // Fix episode titles
            let episodes = try Row.fetchAll(db, sql: "SELECT id, title, description FROM episodes")
            var episodesFixed = 0
            
            for row in episodes {
                let id = row["id"] as String
                let originalTitle = row["title"] as String
                let originalDescription = (row["description"] as String?) ?? ""
                
                var needsUpdate = false
                var newTitle = originalTitle
                var newDescription = originalDescription
                
                // Fix title if it contains HTML entities or is suspiciously empty
                if originalTitle.contains("&#") || originalTitle.contains("&") || originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let decodedTitle = decodeHTMLEntities(originalTitle)
                    if decodedTitle != originalTitle && !decodedTitle.isEmpty {
                        newTitle = decodedTitle
                        needsUpdate = true
                    }
                }
                
                // Fix description if it contains HTML entities
                if originalDescription.contains("&#") || originalDescription.contains("&") {
                    let decodedDescription = decodeHTMLEntities(originalDescription)
                    if decodedDescription != originalDescription {
                        newDescription = decodedDescription
                        needsUpdate = true
                    }
                }
                
                if needsUpdate {
                    try db.execute(sql: "UPDATE episodes SET title = ?, description = ? WHERE id = ?", 
                                 arguments: [newTitle, newDescription, id])
                    episodesFixed += 1
                }
            }
            
            Self.logger.info("Hebrew title repair completed: \(podcastsFixed) podcasts and \(episodesFixed) episodes fixed")
        }
        
        migrator.registerMigration("v13_add_queue_position") { db in
            // Add queuePosition column to playback_state table for queue management
            // This column stores the position of an episode in the queue (1 = first, 2 = second, etc.)
            // NULL means the episode is not in the queue
            do {
                try db.alter(table: "playback_state") { t in
                    t.add(column: "queuePosition", .integer)
                }
                Self.logger.info("Added queuePosition column to playback_state table")
            } catch {
                // Column might already exist in some databases
                Self.logger.info("queuePosition column already exists or error adding it: \(error)")
            }
        }
        
        migrator.registerMigration("v14_integrity_and_played_sync") { db in
            // 1. Sync played bool with status OptionSet:
            //    If status has the played bit (1), ensure played = true
            //    If played = true but status doesn't have the played bit, set it
            try db.execute(sql: """
                UPDATE episodes SET played = 1 WHERE (status & 1) = 1 AND played = 0
            """)
            try db.execute(sql: """
                UPDATE episodes SET status = (status | 1) WHERE played = 1 AND (status & 1) = 0
            """)

            // 2. Clean orphaned playback_state entries (where episode no longer exists)
            try db.execute(sql: """
                DELETE FROM playback_state
                WHERE episodeID NOT IN (SELECT id FROM episodes)
            """)

            // 3. Add index on playback_state.queuePosition for faster queue queries
            try db.create(index: "idx_playback_state_queue_position",
                          on: "playback_state",
                          columns: ["queuePosition"],
                          ifNotExists: true)

            Self.logger.info("v14: Synced played/status, cleaned orphans, added queuePosition index")
        }

        migrator.registerMigration("v15_create_bookmarks") { db in
            try db.create(table: "bookmarks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey().notNull()
                t.column("episodeID", .text).notNull()
                    .references("episodes", column: "id", onDelete: .cascade)
                t.column("timestamp", .double).notNull().defaults(to: 0.0)
                t.column("note", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_bookmarks_episode", on: "bookmarks", columns: ["episodeID"], ifNotExists: true)
            Self.logger.info("v15: Created bookmarks table")
        }

        migrator.registerMigration("v16_add_starred") { db in
            let columns = try db.columns(in: "episodes").map(\.name)
            if !columns.contains("starred") {
                try db.alter(table: "episodes") { t in
                    t.add(column: "starred", .boolean).notNull().defaults(to: false)
                }
            }
            Self.logger.info("v16: Added starred column to episodes")
        }

        migrator.registerMigration("v17_create_transcripts") { db in
            try db.create(table: "episode_transcripts", ifNotExists: true) { t in
                t.column("episodeID", .text).primaryKey()
                    .references("episodes", column: "id", onDelete: .cascade)
                t.column("transcriptURL", .text)
                t.column("format", .text).notNull().defaults(to: "srt")
                t.column("segmentsJSON", .text).notNull().defaults(to: "[]")
                t.column("fetchedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            Self.logger.info("v17: Created episode_transcripts table")
        }

        // Run migrations asynchronously - Use dbPool directly to avoid circular dependency
        guard let pool = dbPool else {
            throw DatabaseError.notInitialized
        }
        try migrator.migrate(pool)
    }

    // MARK: - Async Read/Write Wrappers

    /// Asynchronously writes to the database in a utility-priority background task.
    func writeAsync<T>(_ updates: @escaping (Database) throws -> T) async throws -> T {
        try await (try await getPool()).write { db in
            try updates(db)
        }
    }
    
    /// Asynchronously reads from the database.
    func readAsync<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await (try await getPool()).read { db in
            try block(db)
        }
    }
    
    /// Checks if the database contains any podcasts
    func hasPodcasts() async -> Bool {
        do {
            return try await readAsync { db in
                try Podcast.fetchCount(db) > 0
            }
        } catch {
            return false
        }
    }
    
    /// Perform database health check
    func performHealthCheck() async -> DatabaseHealthStatus {
        do {
            await waitForReady()
            
            // Check if database is accessible
            let podcastCount = try await readAsync { db in
                try Podcast.fetchCount(db)
            }
            
            // Check if tables exist
            let tableNames = try await readAsync { db in
                try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
            }
            
            let hasRequiredTables = tableNames.contains("podcasts") && tableNames.contains("episodes")
            
            return DatabaseHealthStatus(
                isReady: isReady,
                isAccessible: true,
                podcastCount: podcastCount,
                hasRequiredTables: hasRequiredTables,
                tableNames: tableNames
            )
            
        } catch {
            return DatabaseHealthStatus(
                isReady: isReady,
                isAccessible: false,
                podcastCount: 0,
                hasRequiredTables: false,
                tableNames: [],
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Database Statistics
    
    /// Log current database connection pool statistics
    /// Useful for debugging connection issues and monitoring resource usage
    func logDatabaseStats() async {
        await waitForReady()
        
        guard let pool = dbPool else {
            Self.logger.info("Database Stats: Pool not initialized")
            return
        }
        
        do {
            try await pool.read { db in
                // Get WAL mode status
                let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "unknown"
                
                // Get synchronous mode
                let synchronous = try Int.fetchOne(db, sql: "PRAGMA synchronous") ?? -1
                
                // Get database size info
                let pageCount = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
                let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0
                let dbSizeBytes = pageCount * pageSize
                let dbSizeMB = Double(dbSizeBytes) / (1024 * 1024)
                
                // Get table counts
                let podcastCount = try Podcast.fetchCount(db)
                let episodeCount = try Episode.fetchCount(db)
                
                Self.logger.info("""
                📊 Database Stats:
                   ├─ Journal Mode: \(journalMode)
                   ├─ Synchronous: \(synchronous == 1 ? "NORMAL" : "OTHER(\(synchronous))")
                   ├─ Max Readers: 4 (configured)
                   ├─ Busy Timeout: 5.0s (configured)
                   ├─ Database Size: \(String(format: "%.2f", dbSizeMB)) MB
                   ├─ Podcasts: \(podcastCount)
                   └─ Episodes: \(episodeCount)
                """)
            }
        } catch {
            Self.logger.error("Database Stats Error: \(error.localizedDescription)")
        }
    }

    func resetDatabase() async {
        do {
            try await writeAsync { [self] db in
                try db.drop(table: "episodes")
                try db.drop(table: "podcasts")
                try self.createTables(db)
            }
        } catch {
        }
    }

    private func createTables(_ db: Database) throws {
        // Create podcasts table with all required columns
        try db.create(table: "podcasts", ifNotExists: true) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("title", .text).notNull()
            t.column("author", .text).notNull()
            t.column("description", .text)
            t.column("feedURL", .text).notNull().unique()
            t.column("artworkURL", .text)
            t.column("autoAddToQueue", .boolean).notNull().defaults(to: false)
            t.column("notificationsEnabled", .boolean).notNull().defaults(to: false)
            t.column("lastEpisodeDate", .datetime)
            t.column("etag", .text)
            t.column("lastFetched", .datetime)
            t.column("cleanTitle", .text).notNull().defaults(to: "")
            t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }
        
        // Create episodes table
        try db.create(table: "episodes", ifNotExists: true) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("podcastID", .text).notNull().indexed()
                .references("podcasts", column: "id", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("audioURL", .text)
            t.column("publishedDate", .datetime)
            t.column("duration", .double)
            t.column("artworkURL", .text)
            t.column("description", .text)
            t.column("played", .boolean).defaults(to: false)
            t.column("isNew", .boolean).defaults(to: true)
            t.column("localFileURL", .text)
            t.column("playbackPosition", .double).defaults(to: 0.0)
            t.column("page", .integer).notNull().defaults(to: 1)
            t.column("fetchedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            t.column("status", .integer).notNull().defaults(to: 0)
        }
        
        // Create episode_details table
        try db.create(table: "episode_details", ifNotExists: true) { t in
            t.column("episodeID", .text).primaryKey()
                .references("episodes", column: "id", onDelete: .cascade)
            t.column("fullDescription", .text).notNull()
            t.column("chaptersJSON", .text)
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }
        
        // Create playback_state table
        try db.create(table: "playback_state", ifNotExists: true) { t in
            t.column("episodeID", .text).primaryKey()
                .references("episodes", column: "id", onDelete: .cascade)
            t.column("position", .double).notNull().defaults(to: 0.0)
            t.column("finished", .boolean).notNull().defaults(to: false)
            t.column("queuePosition", .integer) // NULL means not in queue, 1 = first in queue
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }
        
        // Create shows table
        try db.create(table: "shows", ifNotExists: true) { t in
            t.column("feedURL", .text).primaryKey()
            t.column("showDescription", .text).notNull()
            t.column("author", .text).notNull()
            t.column("language", .text).notNull()
            t.column("updatedAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        }
    }
    
    /// Create minimal tables for emergency fallback database
    private func createMinimalTables(_ db: Database) throws {
        // Create only the most basic podcasts table
        try db.create(table: "podcasts", ifNotExists: true) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("title", .text).notNull()
            t.column("feedURL", .text).notNull()
        }
        
        // Create only the most basic episodes table
        try db.create(table: "episodes", ifNotExists: true) { t in
            t.column("id", .text).primaryKey().notNull()
            t.column("podcastID", .text).notNull()
            t.column("title", .text).notNull()
        }
    }

    /// Forces a complete database reset - useful for fixing schema issues
    func forceResetDatabase() async {
        
        do {
            // First, try to safely drop tables if they exist
            try await (try await getPool()).write { db in
                // Drop tables in reverse dependency order to avoid foreign key issues
                try? db.execute(sql: "DROP TABLE IF EXISTS episode_details")
                try? db.execute(sql: "DROP TABLE IF EXISTS playback_state") 
                try? db.execute(sql: "DROP TABLE IF EXISTS episodes")
                try? db.execute(sql: "DROP TABLE IF EXISTS podcasts")
                try? db.execute(sql: "DROP TABLE IF EXISTS shows")
            }
            
            // Recreate tables with correct schema
            try await (try await getPool()).write { [self] db in
                try self.createTables(db)
            }
            
        } catch {
            
            // If that fails, try to delete the file and recreate completely
            do {
                // Close the current database pool
                try (try await getPool()).close()
                
                // Delete the database file
                if FileManager.default.fileExists(atPath: dbPath) {
                    try FileManager.default.removeItem(atPath: dbPath)
                }
                
                // Recreate the database with correct schema
                var config = Configuration()
                config.prepareDatabase { db in
                    // db.trace { print("🗄️ SQL: \($0)") }
                    try db.execute(sql: "PRAGMA foreign_keys = ON")
                    // Try WAL mode first, fallback to DELETE mode if it fails
                    do {
                        try db.execute(sql: "PRAGMA journal_mode = WAL")
                    } catch {
                        try db.execute(sql: "PRAGMA journal_mode = DELETE")
                    }
                    try db.execute(sql: "PRAGMA synchronous = NORMAL")
                }
                
                let newPool = try DatabasePool(path: dbPath, configuration: config)
                
                // Create tables directly instead of running migrations
                try await newPool.write { [self] db in
                    try self.createTables(db)
                }
                
                self.dbPool = newPool
                
            } catch {
                
                // Last resort: create a new database file with a different name
                let backupPath = dbPath.replacingOccurrences(of: ".db", with: "_backup_\(Date().timeIntervalSince1970).db")
                
                do {
                            var config = Configuration()
        config.prepareDatabase { db in
            // db.trace { print("🗄️ SQL: \($0)") }
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Try WAL mode first, fallback to DELETE mode if it fails
            do {
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            } catch {
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
            }
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
                    
                    let backupPool = try DatabasePool(path: backupPath, configuration: config)
                    
                    // Create tables
                    try await backupPool.write { db in
                        try self.createTables(db)
                    }
                    
                    self.dbPool = backupPool
                    
                } catch {
                    fatalError("Unable to create database")
                }
            }
        }
    }

    /// Ensure cleanTitle column exists and is populated (safety method)
    func ensureCleanTitleColumn() async {
        do {
            try await writeAsync { db in
                // Check if cleanTitle column exists
                let podcastColumns = try db.columns(in: "podcasts").map(\.name)
                
                if !podcastColumns.contains("cleanTitle") {
                    // Add the column if it doesn't exist
                    try db.alter(table: "podcasts") { t in
                        t.add(column: "cleanTitle", .text).notNull().defaults(to: "")
                    }
                    
                }
                
                // Check if any podcasts have empty cleanTitle and populate them
                let podcastsWithEmptyCleanTitle = try Row.fetchAll(db, sql: "SELECT id, title FROM podcasts WHERE cleanTitle = '' OR cleanTitle IS NULL")
                
                if !podcastsWithEmptyCleanTitle.isEmpty {
                    
                    for row in podcastsWithEmptyCleanTitle {
                        // Handle UUID that might be stored as Data or String
                        let id: String
                        if let uuidData = row["id"] as? Data {
                            // UUID stored as binary data (16 bytes)
                            let uuid = UUID(uuid: uuidData.withUnsafeBytes { $0.load(as: uuid_t.self) })
                            id = uuid.uuidString
                        } else if let uuidString = row["id"] as? String {
                            // UUID stored as string
                            id = uuidString
                        } else {
                            // Skip this row if we can't parse the ID
                            continue
                        }
                        
                        let title: String = row["title"]
                        let cleanTitle = Podcast.processCleanTitle(from: title)
                        
                        try db.execute(
                            sql: "UPDATE podcasts SET cleanTitle = ? WHERE id = ?",
                            arguments: [cleanTitle, id]
                        )
                    }
                    
                }
            }
        } catch {
        }
    }

    private func initializeFallbackDatabase() async {
        do {
            // Try in-memory database as fallback
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                try db.execute(sql: "PRAGMA journal_mode = DELETE") // In-memory doesn't support WAL
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            
            let pool = try DatabasePool(path: ":memory:", configuration: config)
            self.dbPool = pool
            
            try await runMigrations()
            
            await MainActor.run {
                self.isReady = true
            }
        } catch {
            await initializeEmergencyDatabase()
        }
    }
    
    private func initializeEmergencyDatabase() async {
        do {
            // Create the most basic database possible with proper configuration
            var bareMinimumConfig = Configuration()
            bareMinimumConfig.prepareDatabase { db in
                // Use DELETE journal mode for in-memory database (WAL not supported)
                try db.execute(sql: "PRAGMA journal_mode = DELETE")
            }
            
            self.dbPool = try DatabasePool(path: ":memory:", configuration: bareMinimumConfig)
            await MainActor.run {
                self.isReady = true
            }
        } catch {
            // This should never happen, but if it does, we'll create a nil pool
            // and handle it gracefully in getPool()
            await MainActor.run {
                self.isReady = true
            }
        }
    }

    /// Test method to verify queuePosition column exists (for debugging)
    func testQueuePositionColumn() async -> Bool {
        do {
            return try await readAsync { db in
                let columns = try db.columns(in: "playback_state").map(\.name)
                return columns.contains("queuePosition")
            }
        } catch {
            Self.logger.error("Error checking queuePosition column: \(error)")
            return false
        }
    }
    
    /// Get all columns in playback_state table (for debugging)
    func getPlaybackStateColumns() async -> [String] {
        do {
            return try await readAsync { db in
                try db.columns(in: "playback_state").map(\.name)
            }
        } catch {
            Self.logger.error("Error getting playback_state columns: \(error)")
            return []
        }
    }

}

// MARK: - Database Errors

enum DatabaseError: Error {
    case notInitialized
    case migrationFailed(Error)
    case operationFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .notInitialized:
            return "Database is not initialized"
        case .migrationFailed(let error):
            return "Database migration failed: \(error.localizedDescription)"
        case .operationFailed(let error):
            return "Database operation failed: \(error.localizedDescription)"
        }
    }
}






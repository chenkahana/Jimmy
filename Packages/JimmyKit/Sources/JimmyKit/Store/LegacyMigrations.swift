import Foundation
import GRDB
import os

/// Frozen. This is the 17 migrations registered by `runMigrations()` in
/// `Jimmy/Services/DatabaseManager.swift`, copied verbatim: same identifiers, same bodies,
/// same registration order (note `v7_fix_clean_titles` is registered BEFORE
/// `v6_fix_episode_schema` — that is how the shipped app orders them, and `DatabaseMigrator`
/// runs migrations in registration order, not lexical/numeric order, so the order must match
/// exactly for this to open a real `Documents/jimmy.db` without re-running or reordering
/// anything).
///
/// Never edit this file except to fix a compile error that GRDB 7 / Swift 6 forces. Any
/// intentional schema or behavior change belongs in a NEW migration in `Migrations.swift`.
nonisolated enum LegacyMigrations {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LegacyMigrations")

    static func register(on migrator: inout DatabaseMigrator) {
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

        migrator.registerMigration("v3_fix_schema_mismatch") { _ in
            // v1 now includes all required columns, so this migration is no longer needed
            // Keeping this as a no-op to maintain migration history
        }

        migrator.registerMigration("v4_add_clean_title") { _ in
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
                    let cleanTitle = Self.processCleanTitle(from: title)

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
                let newCleanTitle = Self.processCleanTitle(from: title)

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
    }

    /// Copied verbatim from `Jimmy/Models/Podcast.swift`'s `Podcast.processCleanTitle(from:)`.
    /// That type (and its static helper) isn't available to this package, so the logic is
    /// duplicated here rather than changed — this must keep producing byte-for-byte the same
    /// `cleanTitle` values the shipped app's migrations already wrote to disk.
    private static func processCleanTitle(from title: String) -> String {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the cleaned title is empty, return the original title
        guard !cleanedTitle.isEmpty else {
            return title
        }

        // Check for exact duplicate halves (like "The Joe Rogan Experience The Joe Rogan Experience")
        let words = cleanedTitle.components(separatedBy: " ")
        let halfCount = words.count / 2

        if words.count > 1 && words.count % 2 == 0 {
            let firstHalf = Array(words[0..<halfCount]).joined(separator: " ")
            let secondHalf = Array(words[halfCount..<words.count]).joined(separator: " ")

            if firstHalf == secondHalf && !firstHalf.isEmpty {
                return firstHalf
            }
        }

        // Enhanced duplicate detection for case-insensitive matches
        if words.count > 1 && words.count % 2 == 0 {
            let firstHalf = Array(words[0..<halfCount]).joined(separator: " ")
            let secondHalf = Array(words[halfCount..<words.count]).joined(separator: " ")

            if firstHalf.lowercased() == secondHalf.lowercased() && !firstHalf.isEmpty {
                return firstHalf
            }
        }

        // Check for pattern where title is repeated with slight variations or no space
        // Like "The Joe Rogan ExperienceThe Joe Rogan Experience" (no space)
        let lowercased = cleanedTitle.lowercased()
        let length = lowercased.count
        if length > 10 { // Only check for longer titles to avoid false positives
            let midPoint = length / 2
            let firstHalf = String(lowercased.prefix(midPoint))
            let secondHalf = String(lowercased.suffix(length - midPoint))

            if firstHalf == secondHalf {
                return String(cleanedTitle.prefix(midPoint))
            }
        }

        // Check for patterns like "Title Title" where the title is repeated exactly
        let titleComponents = cleanedTitle.components(separatedBy: " ")
        if titleComponents.count >= 4 { // At least 4 words to have meaningful duplicates
            let midPoint = titleComponents.count / 2
            let firstPart = Array(titleComponents[0..<midPoint]).joined(separator: " ")
            let secondPart = Array(titleComponents[midPoint..<titleComponents.count]).joined(separator: " ")

            // Check if the second half exactly matches the first half (case-insensitive)
            if firstPart.lowercased() == secondPart.lowercased() && !firstPart.isEmpty {
                return firstPart
            }
        }

        // Check for titles that are repeated with different patterns
        // Split by common separators and check for duplicates
        let separators = [" - ", " | ", " :: ", ": "]
        for separator in separators {
            let parts = cleanedTitle.components(separatedBy: separator)
            if parts.count == 2 && parts[0].lowercased() == parts[1].lowercased() {
                return parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return cleanedTitle
    }
}

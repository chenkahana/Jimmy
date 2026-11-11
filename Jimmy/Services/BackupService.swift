import Foundation
import GRDB

/// Actor that exports/imports all data as versioned JSON for backup and restore
actor BackupService {
    static let shared = BackupService()

    // MARK: - Backup Format

    struct BackupData: Codable {
        let version: Int = 1
        let createdAt: Date
        let podcasts: [Podcast]
        let episodes: [Episode]
        let playbackStates: [PlaybackState]
        let bookmarks: [Bookmark]
        let settings: [String: String]
    }

    // MARK: - Export

    func exportBackup() async throws -> URL {
        let podcasts = try await DatabaseManager.shared.readAsync { db in
            try Podcast.fetchAll(db)
        }
        let episodes = try await DatabaseManager.shared.readAsync { db in
            try Episode.fetchAll(db)
        }
        let playbackStates = try await DatabaseManager.shared.readAsync { db in
            try PlaybackState.fetchAll(db)
        }
        let bookmarks = try await DatabaseManager.shared.readAsync { db in
            try Bookmark.fetchAll(db)
        }

        // Collect relevant UserDefaults settings
        let settingsKeys = ["playbackSpeed", "skipForwardDuration", "skipBackwardDuration",
                           "darkMode", "episodeSwipeAction", "queueSwipeAction",
                           "autoRestoreLastEpisode", "highContrastMode"]
        var settings: [String: String] = [:]
        for key in settingsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                settings[key] = "\(value)"
            }
        }

        let backup = BackupData(
            createdAt: Date(),
            podcasts: podcasts,
            episodes: episodes,
            playbackStates: playbackStates,
            bookmarks: bookmarks,
            settings: settings
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let fileName = "jimmy_backup_\(ISO8601DateFormatter().string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)

        return url
    }

    // MARK: - Import

    func importBackup(from url: URL) async throws -> (podcasts: Int, episodes: Int) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        // Import podcasts
        try await DatabaseManager.shared.writeAsync { db in
            for podcast in backup.podcasts {
                try podcast.save(db)
            }
        }

        // Import episodes
        try await DatabaseManager.shared.writeAsync { db in
            for episode in backup.episodes {
                try episode.save(db)
            }
        }

        // Import playback states
        try await DatabaseManager.shared.writeAsync { db in
            for state in backup.playbackStates {
                try state.save(db)
            }
        }

        // Import bookmarks
        try await DatabaseManager.shared.writeAsync { db in
            for bookmark in backup.bookmarks {
                try bookmark.save(db)
            }
        }

        // Restore settings
        for (key, value) in backup.settings {
            if let doubleValue = Double(value) {
                UserDefaults.standard.set(doubleValue, forKey: key)
            } else if value == "true" || value == "false" {
                UserDefaults.standard.set(value == "true", forKey: key)
            } else {
                UserDefaults.standard.set(value, forKey: key)
            }
        }

        return (podcasts: backup.podcasts.count, episodes: backup.episodes.count)
    }
}

import Foundation
import JimmyKit

/// Actor that exports/imports all data as versioned JSON for backup and restore, through
/// `AppModel`'s `Store` rather than a hand-rolled `DatabaseManager` read/write of the legacy GRDB
/// models.
actor BackupService {
    static let shared = BackupService()

    // MARK: - Backup Format

    struct BackupData: Codable {
        let version: Int = 2
        let createdAt: Date
        let podcasts: [JimmyKit.Podcast]
        let episodes: [JimmyKit.Episode]
        let progress: [JimmyKit.Progress]
        let bookmarks: [JimmyKit.Bookmark]
        let settings: [String: String]
    }

    // MARK: - Export

    func exportBackup() async throws -> URL {
        guard let store = await AppModel.current?.readyStore else { throw AppModelError.storeNotReady }

        let podcasts = try await store.podcasts()
        let episodes = try await store.allEpisodes()
        let progress = try await store.allProgress()
        let bookmarks = try await store.allBookmarks()

        // Collect relevant UserDefaults settings
        let settingsKeys = ["playbackSpeed", "skipForwardDuration", "skipBackwardDuration",
                           "appearanceMode", "episodeSwipeAction", "queueSwipeAction",
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
            progress: progress,
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
        guard let store = await AppModel.current?.readyStore else { throw AppModelError.storeNotReady }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        try await store.restore(
            podcasts: backup.podcasts,
            episodes: backup.episodes,
            progress: backup.progress,
            bookmarks: backup.bookmarks
        )

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

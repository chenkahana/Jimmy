import Foundation
import GRDB

/// Service for fetching and parsing podcast chapters from various sources
final class ChapterService {
    static let shared = ChapterService()
    private init() {}

    /// Fetch chapters from a Podcasting 2.0 JSON Chapters URL
    func fetchChapters(from url: URL) async throws -> [Chapter] {
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ChaptersResponse.self, from: data)
        return response.chapters
    }

    /// Parse chapters from existing chaptersJSON string (stored in episode_details)
    func parseChaptersJSON(_ json: String) -> [Chapter]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Chapter].self, from: data)
    }

    /// Save chapters to episode_details.chaptersJSON
    func saveChapters(_ chapters: [Chapter], for episodeID: UUID) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(chapters)
        let json = String(data: data, encoding: .utf8) ?? "[]"

        try await DatabaseManager.shared.writeAsync { db in
            // Check if episode_details row exists
            let exists = try Row.fetchOne(db, sql: "SELECT 1 FROM episode_details WHERE episodeID = ?", arguments: [episodeID.uuidString]) != nil
            if exists {
                try db.execute(sql: "UPDATE episode_details SET chaptersJSON = ?, updatedAt = ? WHERE episodeID = ?",
                               arguments: [json, Date(), episodeID.uuidString])
            } else {
                try db.execute(sql: "INSERT INTO episode_details (episodeID, fullDescription, chaptersJSON, updatedAt) VALUES (?, '', ?, ?)",
                               arguments: [episodeID.uuidString, json, Date()])
            }
        }
    }

    /// Load chapters for an episode from the database
    func loadChapters(for episodeID: UUID) async -> [Chapter] {
        do {
            let json: String? = try await DatabaseManager.shared.readAsync { db in
                try String.fetchOne(db, sql: "SELECT chaptersJSON FROM episode_details WHERE episodeID = ?", arguments: [episodeID.uuidString])
            }
            guard let json = json else { return [] }
            return parseChaptersJSON(json) ?? []
        } catch {
            return []
        }
    }
}

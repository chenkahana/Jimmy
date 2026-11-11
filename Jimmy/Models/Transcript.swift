import Foundation
import GRDB

/// A single segment of a transcript with timing information
struct TranscriptSegment: Codable, Equatable, Identifiable {
    var id: String { "\(startTime)" }
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var speaker: String?
}

/// Database record for episode transcripts
struct EpisodeTranscript: Codable, Equatable, FetchableRecord, PersistableRecord {
    var episodeID: UUID
    var transcriptURL: String?
    var format: String // "srt", "vtt", or "json"
    var segmentsJSON: String // JSON-encoded [TranscriptSegment]
    var fetchedAt: Date

    static var databaseTableName: String = "episode_transcripts"

    enum Columns: String, ColumnExpression {
        case episodeID, transcriptURL, format, segmentsJSON, fetchedAt
    }

    init(episodeID: UUID, transcriptURL: String? = nil, format: String, segmentsJSON: String, fetchedAt: Date = Date()) {
        self.episodeID = episodeID
        self.transcriptURL = transcriptURL
        self.format = format
        self.segmentsJSON = segmentsJSON
        self.fetchedAt = fetchedAt
    }

    init(row: Row) {
        if let uuidString = row[Columns.episodeID] as? String {
            episodeID = UUID(uuidString: uuidString) ?? UUID()
        } else {
            episodeID = UUID()
        }
        transcriptURL = row[Columns.transcriptURL]
        format = row[Columns.format]
        segmentsJSON = row[Columns.segmentsJSON]
        fetchedAt = row[Columns.fetchedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.episodeID] = episodeID.uuidString
        container[Columns.transcriptURL] = transcriptURL
        container[Columns.format] = format
        container[Columns.segmentsJSON] = segmentsJSON
        container[Columns.fetchedAt] = fetchedAt
    }

    /// Decode segments from JSON
    var segments: [TranscriptSegment] {
        guard let data = segmentsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
    }
}

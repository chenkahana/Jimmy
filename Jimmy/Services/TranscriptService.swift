import Foundation
import GRDB

/// Fetches and parses transcripts in SRT, VTT, and Podcasting 2.0 JSON formats
final class TranscriptService {
    static let shared = TranscriptService()
    private init() {}

    // MARK: - Fetch & Parse

    func fetchTranscript(from url: URL) async throws -> [TranscriptSegment] {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let urlString = url.absoluteString.lowercased()
        if urlString.hasSuffix(".srt") {
            return parseSRT(text)
        } else if urlString.hasSuffix(".vtt") {
            return parseVTT(text)
        } else if urlString.hasSuffix(".json") {
            return parseJSON(data)
        }

        // Try to detect format from content
        if text.contains("WEBVTT") {
            return parseVTT(text)
        } else if text.contains("-->") {
            return parseSRT(text)
        }
        return parseJSON(data)
    }

    // MARK: - SRT Parser

    func parseSRT(_ text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let blocks = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 3 else { continue }

            // Line 1: index number (skip)
            // Line 2: timestamps "00:00:01,000 --> 00:00:05,000"
            let timeLine = lines[1]
            guard let (start, end) = parseTimestampLine(timeLine) else { continue }

            // Lines 3+: text content
            let segmentText = lines[2...].joined(separator: " ")

            segments.append(TranscriptSegment(startTime: start, endTime: end, text: segmentText))
        }
        return segments
    }

    // MARK: - VTT Parser

    func parseVTT(_ text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // Look for timestamp lines
            if line.contains("-->") {
                guard let (start, end) = parseTimestampLine(line) else {
                    i += 1
                    continue
                }

                // Collect text lines until empty line
                var textLines: [String] = []
                i += 1
                while i < lines.count {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if nextLine.isEmpty { break }
                    textLines.append(nextLine)
                    i += 1
                }

                let segmentText = textLines.joined(separator: " ")
                if !segmentText.isEmpty {
                    segments.append(TranscriptSegment(startTime: start, endTime: end, text: segmentText))
                }
            }
            i += 1
        }
        return segments
    }

    // MARK: - JSON Parser (Podcasting 2.0)

    func parseJSON(_ data: Data) -> [TranscriptSegment] {
        // Try Podcasting 2.0 format: { "segments": [...] }
        if let response = try? JSONDecoder().decode(TranscriptJSONResponse.self, from: data) {
            return response.segments
        }
        // Try direct array format
        return (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
    }

    // MARK: - Storage

    func saveTranscript(for episodeID: UUID, segments: [TranscriptSegment], url: String?, format: String) async throws {
        let encoder = JSONEncoder()
        let json = String(data: try encoder.encode(segments), encoding: .utf8) ?? "[]"
        let record = EpisodeTranscript(episodeID: episodeID, transcriptURL: url, format: format, segmentsJSON: json)
        try await DatabaseManager.shared.writeAsync { db in
            try record.save(db)
        }
    }

    func loadTranscript(for episodeID: UUID) async -> EpisodeTranscript? {
        try? await DatabaseManager.shared.readAsync { db in
            try EpisodeTranscript.fetchOne(db, key: episodeID.uuidString)
        }
    }

    // MARK: - Private Helpers

    private func parseTimestampLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
        let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces))
        guard let s = start, let e = end else { return nil }
        return (s, e)
    }

    private func parseTimestamp(_ str: String) -> TimeInterval? {
        // Supports "HH:MM:SS,mmm", "HH:MM:SS.mmm", "MM:SS.mmm"
        let cleaned = str.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        if parts.count == 3 {
            guard let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
            return h * 3600 + m * 60 + s
        } else {
            guard let m = Double(parts[0]), let s = Double(parts[1]) else { return nil }
            return m * 60 + s
        }
    }
}

// JSON transcript response format
private struct TranscriptJSONResponse: Codable {
    let segments: [TranscriptSegment]
}

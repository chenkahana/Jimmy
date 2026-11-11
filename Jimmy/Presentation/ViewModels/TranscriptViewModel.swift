import Foundation
import JimmyKit
import Combine
import Observation
import os

/// Syncs current transcript segment to playback position, supports search. Read and written
/// through `AppModel`/`Store` directly; fetching and parsing a transcript file from its URL
/// (SRT/VTT/Podcasting 2.0 JSON) is this view model's own job — the store only persists the
/// already-parsed result.
@MainActor
class TranscriptViewModel: ObservableObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "TranscriptViewModel")
    @Published var segments: [TranscriptSegment] = []
    @Published var currentSegment: TranscriptSegment?
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var hasTranscript = false

    private let episodeID: UUID

    var filteredSegments: [TranscriptSegment] {
        if searchText.isEmpty { return segments }
        return segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    init(episodeID: UUID) {
        self.episodeID = episodeID
        observePlaybackPosition()
        Task { await loadTranscript() }
    }

    func loadTranscript() async {
        isLoading = true
        if let transcript = await AppModel.current?.transcript(for: episodeID) {
            segments = transcript.segments ?? []
            hasTranscript = !segments.isEmpty
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        }
        isLoading = false
    }

    func fetchTranscript(from url: URL) async {
        isLoading = true
        do {
            let fetched = try await TranscriptFileParser.fetchAndParse(from: url)
            let format: TranscriptFormat = url.pathExtension.lowercased() == "srt" ? .srt
                : url.pathExtension.lowercased() == "vtt" ? .vtt : .json
            let transcript = Transcript(episodeID: episodeID, url: url, format: format, segments: fetched)
            await AppModel.current?.saveTranscript(transcript)
            segments = fetched
            hasTranscript = !fetched.isEmpty
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        } catch {
            Self.logger.error("Failed to fetch transcript: \(error)")
        }
        isLoading = false
    }

    /// `Playback` is `@Observable`, not an `ObservableObject` this Combine-based view model can
    /// subscribe to — track `position` and re-register on every change instead.
    private func observePlaybackPosition() {
        withObservationTracking {
            updateCurrentSegment(for: AppModel.current?.playback?.position ?? 0)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePlaybackPosition()
            }
        }
    }

    private func updateCurrentSegment(for position: TimeInterval) {
        let segment = segments.last { $0.startTime <= position && position < $0.endTime }
        if segment?.startTime != currentSegment?.startTime {
            currentSegment = segment
        }
    }
}

/// Fetches and parses a transcript file in SRT, VTT, or Podcasting 2.0 JSON format. Pure
/// parsing — no database or network state of its own, so it needs no `Store` surface.
enum TranscriptFileParser {
    static func fetchAndParse(from url: URL) async throws -> [TranscriptSegment] {
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

        if text.contains("WEBVTT") {
            return parseVTT(text)
        } else if text.contains("-->") {
            return parseSRT(text)
        }
        return parseJSON(data)
    }

    static func parseSRT(_ text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let blocks = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard lines.count >= 3 else { continue }

            let timeLine = lines[1]
            guard let (start, end) = parseTimestampLine(timeLine) else { continue }

            let segmentText = lines[2...].joined(separator: " ")
            segments.append(TranscriptSegment(startTime: start, endTime: end, text: segmentText))
        }
        return segments
    }

    static func parseVTT(_ text: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if line.contains("-->") {
                guard let (start, end) = parseTimestampLine(line) else {
                    i += 1
                    continue
                }

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

    static func parseJSON(_ data: Data) -> [TranscriptSegment] {
        if let response = try? JSONDecoder().decode(TranscriptJSONResponse.self, from: data) {
            return response.segments
        }
        return (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
    }

    private static func parseTimestampLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
        let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces))
        guard let s = start, let e = end else { return nil }
        return (s, e)
    }

    private static func parseTimestamp(_ str: String) -> TimeInterval? {
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

private struct TranscriptJSONResponse: Codable {
    let segments: [TranscriptSegment]
}

import Foundation

/// The source format of a transcript file.
public enum TranscriptFormat: String, Sendable, Hashable, Codable {
    case srt
    case vtt
    case json
}

/// A single timed, speaker-attributed line of a transcript.
public nonisolated struct TranscriptSegment: Sendable, Hashable, Codable {
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var speaker: String?

    public init(startTime: TimeInterval, endTime: TimeInterval, text: String, speaker: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
    }
}

/// An episode's transcript. `segments` is nil until parsed from the fetched file at `url`.
public nonisolated struct Transcript: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { episodeID }
    public var episodeID: UUID
    public var url: URL
    public var format: TranscriptFormat
    public var segments: [TranscriptSegment]?

    public init(episodeID: UUID, url: URL, format: TranscriptFormat, segments: [TranscriptSegment]? = nil) {
        self.episodeID = episodeID
        self.url = url
        self.format = format
        self.segments = segments
    }
}

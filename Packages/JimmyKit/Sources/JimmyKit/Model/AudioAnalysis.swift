import Foundation

/// What an offline pass over a downloaded episode's audio found: how loud it is, and where it is
/// quiet. Stored per episode so volume boost can use an exact gain from the first second and
/// skip silence knows where the pauses are.
public nonisolated struct AudioAnalysis: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID { episodeID }
    public var episodeID: UUID
    /// Integrated loudness in LUFS, or `nil` for audio with nothing loud enough to measure.
    public var integratedLUFS: Double?
    /// Highest absolute sample, linear (1.0 is full scale).
    public var samplePeak: Double
    public var silenceRanges: [SilenceRange]
    public var analyzedAt: Date

    public init(
        episodeID: UUID,
        integratedLUFS: Double?,
        samplePeak: Double,
        silenceRanges: [SilenceRange],
        analyzedAt: Date = Date()
    ) {
        self.episodeID = episodeID
        self.integratedLUFS = integratedLUFS
        self.samplePeak = samplePeak
        self.silenceRanges = silenceRanges
        self.analyzedAt = analyzedAt
    }

    /// Total time the silence ranges would save, in seconds.
    public var skippableDuration: TimeInterval {
        silenceRanges.reduce(0) { $0 + $1.duration }
    }
}

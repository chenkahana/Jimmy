import Foundation

/// A stretch of an episode that is quiet enough to skip, in seconds from the start.
public nonisolated struct SilenceRange: Sendable, Hashable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

/// Finds the pauses in an episode so playback can skip them.
///
/// Audio is judged in 10 ms windows. A window is silent when its RMS is below `thresholdDBFS`
/// (-45 by default). A run of silent windows becomes a range only when it lasts at least
/// `minimumDuration` (0.4 s). Each range is then trimmed by `padding` (0.12 s) at both ends, so
/// the first and last bit of every pause still plays and no word gets clipped.
///
/// Feed samples in any chunk size, one value per frame (the caller reduces channels, for example
/// to the louder of the two); call `finish(totalDuration:)` at the end. Offline use only.
public nonisolated struct SilenceDetector: Sendable {
    public let sampleRate: Double
    public let thresholdDBFS: Double
    public let minimumDuration: TimeInterval
    public let padding: TimeInterval

    private let windowLength: Int
    private var windowFill = 0
    private var windowSum = 0.0
    private var windowIndex = 0
    private var runStartWindow: Int?
    private var ranges: [SilenceRange] = []

    public init(
        sampleRate: Double,
        thresholdDBFS: Double = -45,
        minimumDuration: TimeInterval = 0.4,
        padding: TimeInterval = 0.12
    ) {
        precondition(sampleRate > 0)
        self.sampleRate = sampleRate
        self.thresholdDBFS = thresholdDBFS
        self.minimumDuration = minimumDuration
        self.padding = padding
        self.windowLength = max(1, Int((sampleRate * 0.01).rounded()))
    }

    private var windowSeconds: Double { Double(windowLength) / sampleRate }

    public mutating func process(_ samples: [Float]) {
        let limit = pow(10, thresholdDBFS / 10)
        for sample in samples {
            windowSum += Double(sample) * Double(sample)
            windowFill += 1
            if windowFill == windowLength {
                let isSilent = windowSum / Double(windowLength) < limit
                closeWindow(silent: isSilent)
                windowFill = 0
                windowSum = 0
            }
        }
    }

    /// The ranges found, once all audio has been fed. A pause that runs to the end of the audio
    /// counts like any other.
    public mutating func finish() -> [SilenceRange] {
        if windowFill > 0 { closeWindow(silent: false) }
        endRun(atWindow: windowIndex)
        return ranges
    }

    private mutating func closeWindow(silent: Bool) {
        if silent {
            if runStartWindow == nil { runStartWindow = windowIndex }
        } else {
            endRun(atWindow: windowIndex)
        }
        windowIndex += 1
    }

    private mutating func endRun(atWindow end: Int) {
        guard let startWindow = runStartWindow else { return }
        runStartWindow = nil
        let start = Double(startWindow) * windowSeconds
        let stop = Double(end) * windowSeconds
        guard stop - start >= minimumDuration else { return }
        let padded = SilenceRange(start: start + padding, end: stop - padding)
        if padded.duration > 0 { ranges.append(padded) }
    }
}

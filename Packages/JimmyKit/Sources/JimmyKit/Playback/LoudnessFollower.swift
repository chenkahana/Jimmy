import Foundation

/// A running loudness estimate for audio that is playing right now, so a streamed episode can be
/// leveled before anything has been measured end to end.
///
/// It reads K-weighted power through two smoothers: a fast one (0.4 s) that follows the signal and
/// a slow one (8 s) that only moves while the fast one is above -60 LUFS and within 10 LU of the
/// slow one, so pauses and sound effects don't pull the estimate around. The estimate is `nil`
/// for the first 0.8 s, while the fast smoother settles.
///
/// Real-time safe like `LoudnessProcessor`: nothing is allocated after `init`, no locks. It only
/// reads the audio, so it can sit next to the processor and see the unprocessed signal.
public nonisolated final class LoudnessFollower: @unchecked Sendable {
    /// The slow estimate in LUFS, once there is one.
    public private(set) var estimatedLUFS: Double?

    private let channelCount: Int
    private var left: KWeighting
    private var right: KWeighting
    private let fastCoefficient: Double
    private let slowCoefficient: Double
    private let warmUpFrames: Int
    private var framesSeen = 0
    private var fastPower = 0.0
    private var slowPower = 0.0

    public init(sampleRate: Double, channelCount: Int) {
        precondition(sampleRate > 0 && (1...2).contains(channelCount))
        self.channelCount = channelCount
        self.left = KWeighting(sampleRate: sampleRate)
        self.right = KWeighting(sampleRate: sampleRate)
        self.fastCoefficient = 1 - exp(-1 / (0.4 * sampleRate))
        self.slowCoefficient = 1 - exp(-1 / (8 * sampleRate))
        self.warmUpFrames = Int(sampleRate * 0.8)
    }

    /// Reads `frameCount` frames. Pass `right: nil` for mono. Strides work as in
    /// `LoudnessProcessor.process`.
    public func process(
        left leftSamples: UnsafePointer<Float>,
        right rightSamples: UnsafePointer<Float>?,
        frameCount: Int,
        leftStride: Int = 1,
        rightStride: Int = 1
    ) {
        for frame in 0..<frameCount {
            let l = left.process(Double(leftSamples[frame * leftStride]))
            var power = l * l
            if channelCount == 2, let rightSamples {
                let r = right.process(Double(rightSamples[frame * rightStride]))
                power += r * r
            }
            fastPower += (power - fastPower) * fastCoefficient
            framesSeen += 1
            guard framesSeen > warmUpFrames else { continue }

            let fastLUFS = LoudnessMeter.lufs(forPower: fastPower)
            guard fastLUFS > -60 else { continue }
            if estimatedLUFS == nil {
                slowPower = fastPower
                estimatedLUFS = fastLUFS
            } else if fastLUFS > LoudnessMeter.lufs(forPower: slowPower) - 10 {
                slowPower += (fastPower - slowPower) * slowCoefficient
                estimatedLUFS = LoudnessMeter.lufs(forPower: slowPower)
            }
        }
    }
}

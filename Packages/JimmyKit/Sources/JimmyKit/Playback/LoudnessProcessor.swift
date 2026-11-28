import Foundation

/// The real-time part of volume boost: a gain stage, an optional light compressor and a
/// look-ahead limiter, applied in place to audio buffers.
///
/// Built to run inside an audio callback: everything it needs is allocated in `init`, and
/// `process` allocates nothing, takes no locks and calls no Swift runtime features that do.
/// It is not thread safe by itself. One thread (the audio thread) calls `process`; the owner
/// changes `targetGainDB` from elsewhere only through a mechanism it provides (the tap wiring
/// passes it across with an atomic), so this type stays free of locks.
///
/// Signal chain, per frame:
/// 1. Gain eases toward `targetGainDB` (about 200 ms), so a changing estimate never jumps.
/// 2. Compressor (when on): about 2:1 above -24 dBFS with a 6 dB soft knee, slow release, so quiet
///    voices come up without pumping. It follows the stereo-linked RMS level.
/// 3. Limiter: holds peaks at or under `ceilingDBFS` using 2 ms of look-ahead, so the gain can
///    never clip. That look-ahead is the processor's only latency (`latencyFrames`).
public nonisolated final class LoudnessProcessor: @unchecked Sendable {
    public static let ceilingDBFS: Double = -1
    public static let compressorThresholdDBFS: Double = -24
    public static let compressorRatio: Double = 2
    public static let compressorKneeDB: Double = 6

    /// Gain the processor eases toward, in dB. Clamped to ±`VolumeBoost.maxGainDB`.
    public var targetGainDB: Double {
        get { target }
        set {
            target = min(VolumeBoost.maxGainDB, max(-VolumeBoost.maxGainDB, newValue))
            targetLinear = pow(10, target / 20)
        }
    }
    public var compressorEnabled: Bool

    /// Frames of delay the limiter's look-ahead adds.
    public let latencyFrames: Int

    private var target: Double
    private var targetLinear: Double
    private var gain: Double

    private let ceiling: Float
    private let gainSmoothing: Double
    private let detectorSmoothing: Double
    private let attackSmoothing: Double
    private let releaseSmoothing: Double
    private var meanSquare = 0.0
    private var reductionDB = 0.0

    // Limiter state. `window` is the look-ahead length in frames.
    private let window: Int
    private var position = 0
    private let delayLeft: UnsafeMutablePointer<Float>
    private let delayRight: UnsafeMutablePointer<Float>
    /// Required limiter gain per frame, for the last `window` frames.
    private let required: UnsafeMutablePointer<Float>
    /// Window minimum of `required` per frame, for the last `window` frames.
    private let held: UnsafeMutablePointer<Float>
    private var heldSum = 0.0

    public init(sampleRate: Double, gainDB: Double = 0, compressorEnabled: Bool = false) {
        precondition(sampleRate > 0)
        let clamped = min(VolumeBoost.maxGainDB, max(-VolumeBoost.maxGainDB, gainDB))
        self.target = clamped
        self.targetLinear = pow(10, clamped / 20)
        self.gain = targetLinear
        self.compressorEnabled = compressorEnabled
        self.ceiling = Float(pow(10, Self.ceilingDBFS / 20))
        self.gainSmoothing = Self.smoothingCoefficient(timeConstant: 0.2, sampleRate: sampleRate)
        self.detectorSmoothing = Self.smoothingCoefficient(timeConstant: 0.03, sampleRate: sampleRate)
        self.attackSmoothing = Self.smoothingCoefficient(timeConstant: 0.02, sampleRate: sampleRate)
        self.releaseSmoothing = Self.smoothingCoefficient(timeConstant: 0.4, sampleRate: sampleRate)
        let window = max(2, Int((sampleRate * 0.002).rounded()))
        self.window = window
        self.latencyFrames = window - 1
        delayLeft = .allocate(capacity: window)
        delayRight = .allocate(capacity: window)
        required = .allocate(capacity: window)
        held = .allocate(capacity: window)
        delayLeft.initialize(repeating: 0, count: window)
        delayRight.initialize(repeating: 0, count: window)
        required.initialize(repeating: 1, count: window)
        held.initialize(repeating: 1, count: window)
        self.heldSum = Double(window)
    }

    deinit {
        delayLeft.deallocate()
        delayRight.deallocate()
        required.deallocate()
        held.deallocate()
    }

    /// Processes `frameCount` frames in place. Pass `right: nil` for mono. The strides let one
    /// routine handle both layouts: 1 for separate (planar) channel buffers, 2 for interleaved
    /// stereo (`left` at the start, `right` one sample after it).
    public func process(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>?,
        frameCount: Int,
        leftStride: Int = 1,
        rightStride: Int = 1
    ) {
        let thresholdDB = Self.compressorThresholdDBFS
        let ratio = Self.compressorRatio
        let knee = Self.compressorKneeDB
        for frame in 0..<frameCount {
            gain += (targetLinear - gain) * gainSmoothing

            var l = left[frame * leftStride] * Float(gain)
            var r = l
            if let right { r = right[frame * rightStride] * Float(gain) }

            if compressorEnabled {
                let power = Double(max(l * l, r * r))
                meanSquare += (power - meanSquare) * detectorSmoothing
                let levelDB = 10 * log10(max(meanSquare, 1e-12))
                let over = levelDB - thresholdDB
                var wantedDB = 0.0
                if 2 * over > knee {
                    wantedDB = over / ratio - over
                } else if 2 * over > -knee {
                    let x = over + knee / 2
                    wantedDB = (1 / ratio - 1) * x * x / (2 * knee)
                }
                let coefficient = wantedDB < reductionDB ? attackSmoothing : releaseSmoothing
                reductionDB += (wantedDB - reductionDB) * coefficient
                let compression = Float(pow(10, reductionDB / 20))
                l *= compression
                r *= compression
            }

            // Limiter. Record the delayed input and the gain this frame needs.
            let peak = max(abs(l), abs(r))
            let needed: Float = peak > ceiling ? ceiling / peak : 1
            let slot = position
            let next = slot + 1 == window ? 0 : slot + 1
            delayLeft[slot] = l
            delayRight[slot] = r
            required[slot] = needed
            // The slot after the newest one holds the input from `window - 1` frames ago: the
            // delay at which the averaged gain below is guaranteed to cover its peak.
            let outLeft = delayLeft[next]
            let outRight = delayRight[next]

            // Minimum of `required` over the whole window, then averaged over the window.
            var minimum = needed
            for index in 0..<window where required[index] < minimum { minimum = required[index] }
            heldSum += Double(minimum) - Double(held[slot])
            held[slot] = minimum
            let limiterGain = Float(heldSum / Double(window))
            position = next

            left[frame * leftStride] = outLeft * limiterGain
            if let right { right[frame * rightStride] = outRight * limiterGain }
        }
    }

    /// One-pole smoothing coefficient: the fraction of the remaining distance covered each frame.
    private static func smoothingCoefficient(timeConstant: Double, sampleRate: Double) -> Double {
        1 - exp(-1 / (timeConstant * sampleRate))
    }
}

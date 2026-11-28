import Foundation

/// A light voice EQ: the "Voice clarity" setting.
///
/// Two filters per channel, RBJ-cookbook biquads:
/// - an 80 Hz high-pass (Butterworth, Q 0.707) that removes rumble, handling noise and plosive
///   thump that make speech sound boxy (-3 dB at 80 Hz, -17 dB at 30 Hz, nearly flat by 200 Hz);
/// - a wide +2.5 dB peak at 3 kHz (Q 0.9) in the speech presence band, where consonants and
///   intelligibility live (+1.6 dB at 2 kHz, +1.2 dB at 5 kHz, under 0.4 dB at 1 kHz and 10 kHz).
///
/// The shape is a conservative starting point from common speech-mastering practice, not a
/// copy of any other app. It is meant to be judged by ear in an A/B, then tuned.
///
/// Real-time safe: no allocation after `init`, no locks. The presence boost can add up to 2.5 dB
/// of peak, so it must run before the limiter in `LoudnessProcessor`.
public nonisolated final class VoiceEQ: @unchecked Sendable {
    public static let highPassHz = 80.0
    public static let presenceHz = 3_000.0
    public static let presenceGainDB = 2.5

    private struct Biquad {
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var z1 = 0.0, z2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private var highPassLeft = Biquad()
    private var highPassRight = Biquad()
    private var presenceLeft = Biquad()
    private var presenceRight = Biquad()

    public init(sampleRate: Double) {
        precondition(sampleRate > 0)
        // High-pass.
        var w0 = 2 * Double.pi * Self.highPassHz / sampleRate
        var cosine = cos(w0)
        var alpha = sin(w0) / (2 * 0.7071067811865476)
        var a0 = 1 + alpha
        var highPass = Biquad()
        highPass.b0 = (1 + cosine) / 2 / a0
        highPass.b1 = -(1 + cosine) / a0
        highPass.b2 = (1 + cosine) / 2 / a0
        highPass.a1 = -2 * cosine / a0
        highPass.a2 = (1 - alpha) / a0
        highPassLeft = highPass
        highPassRight = highPass

        // Presence peak.
        let amplitude = pow(10, Self.presenceGainDB / 40)
        w0 = 2 * Double.pi * Self.presenceHz / sampleRate
        cosine = cos(w0)
        alpha = sin(w0) / (2 * 0.9)
        a0 = 1 + alpha / amplitude
        var presence = Biquad()
        presence.b0 = (1 + alpha * amplitude) / a0
        presence.b1 = -2 * cosine / a0
        presence.b2 = (1 - alpha * amplitude) / a0
        presence.a1 = -2 * cosine / a0
        presence.a2 = (1 - alpha / amplitude) / a0
        presenceLeft = presence
        presenceRight = presence
    }

    /// Filters `frameCount` frames in place. Pass `right: nil` for mono. Strides work as in
    /// `LoudnessProcessor.process`.
    public func process(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>?,
        frameCount: Int,
        leftStride: Int = 1,
        rightStride: Int = 1
    ) {
        for frame in 0..<frameCount {
            let l = left[frame * leftStride]
            left[frame * leftStride] = Float(presenceLeft.process(highPassLeft.process(Double(l))))
            if let right {
                let r = right[frame * rightStride]
                right[frame * rightStride] = Float(presenceRight.process(highPassRight.process(Double(r))))
            }
        }
    }
}

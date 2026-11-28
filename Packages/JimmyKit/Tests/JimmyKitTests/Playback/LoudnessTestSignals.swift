import Foundation

/// Synthetic audio for the loudness tests.
enum LoudnessTestSignals {
    static func sine(amplitude: Double, frequency: Double = 997, seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
    }

    /// A ±`amplitude` square wave that flips every 50 frames.
    static func square(amplitude: Float, seconds: Double, sampleRate: Double = 48_000) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { ($0 / 50) % 2 == 0 ? amplitude : -amplitude }
    }

    static func peak(_ samples: ArraySlice<Float>) -> Float {
        samples.reduce(0) { max($0, abs($1)) }
    }
}

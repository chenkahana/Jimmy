import Foundation
import AVFoundation

/// Picks how `AVPlayer` keeps the pitch of speech natural when it plays faster or slower than
/// normal. One place decides it, so the engine never carries scattered conditionals.
///
/// `.spectral` is the higher-quality algorithm and gives cleaner speech at 1.25x and above, at a
/// higher CPU cost. `.timeDomain` is cheaper, so it stays the choice on the Watch and in Low Power
/// Mode. At 1.0x the algorithm has no audible effect, so the cheaper one is used there too.
public nonisolated enum PlaybackQuality {
    public static func pitchAlgorithm(rate: Float, cheapProcessing: Bool) -> AVAudioTimePitchAlgorithm {
        if cheapProcessing || rate == 1.0 { return .timeDomain }
        return .spectral
    }

    /// Whether this process should favor battery over pitch quality: always on watchOS, and on
    /// other platforms while Low Power Mode is on.
    public static var prefersCheapProcessing: Bool {
        #if os(watchOS)
        return true
        #else
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #endif
    }
}

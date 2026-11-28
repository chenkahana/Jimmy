import Foundation

/// The "Volume boost" player setting: how loud episodes are leveled. Off leaves the audio
/// untouched, Normal matches the common podcast target, High is louder for noisy places.
public nonisolated enum VolumeBoost: String, Sendable, CaseIterable, Codable {
    case off
    case normal
    case high

    /// Integrated loudness to level episodes to, in LUFS. `nil` when off.
    public var targetLUFS: Double? {
        switch self {
        case .off: nil
        case .normal: -16
        case .high: -14
        }
    }

    /// Largest gain the leveler applies in either direction, in dB. It keeps a mis-measured
    /// episode from being boosted into noise or cut into silence.
    public static let maxGainDB: Double = 12

    /// The per-episode gain that brings an episode measured at `measuredLUFS` to this level, in
    /// dB, clamped to ±`maxGainDB`. Zero when off or when there is no measurement yet.
    public func gainDB(measuredLUFS: Double?) -> Double {
        guard let target = targetLUFS, let measured = measuredLUFS, measured.isFinite else { return 0 }
        return min(Self.maxGainDB, max(-Self.maxGainDB, target - measured))
    }
}

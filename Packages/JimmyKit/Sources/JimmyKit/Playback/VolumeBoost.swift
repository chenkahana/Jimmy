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

    /// Whether the light compressor runs. Only High does: it lifts quiet voices for noisy places.
    public var usesCompressor: Bool { self == .high }

    /// The level new installs start at. Off until the on-device listening check against Apple
    /// Podcasts is done; the plan's goal is Normal, so flipping this one line turns it on.
    public static let defaultLevel: VolumeBoost = .off

    /// UserDefaults key the setting is stored under (a raw value string).
    public static let defaultsKey = "volumeBoost"

    /// The stored level, or `defaultLevel` when nothing valid is stored.
    public static func stored(in defaults: UserDefaults = .standard) -> VolumeBoost {
        defaults.string(forKey: defaultsKey).flatMap(VolumeBoost.init(rawValue:)) ?? defaultLevel
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

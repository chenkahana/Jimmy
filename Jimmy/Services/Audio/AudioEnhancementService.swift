import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Enhancement Levels

enum TrimSilenceLevel: String, CaseIterable, Identifiable {
    case off = "Off"
    case mild = "Mild"
    case medium = "Medium"
    case aggressive = "Aggressive"

    var id: String { rawValue }

    /// Minimum silence duration (seconds) before skipping
    var threshold: TimeInterval {
        switch self {
        case .off: return 0
        case .mild: return 0.5
        case .medium: return 0.3
        case .aggressive: return 0.2
        }
    }

    /// RMS level below which audio is considered silence
    var rmsThreshold: Float {
        switch self {
        case .off: return 0
        case .mild: return 0.01
        case .medium: return 0.015
        case .aggressive: return 0.02
        }
    }
}

enum VolumeBoostLevel: String, CaseIterable, Identifiable {
    case off = "Off"
    case low = "+3 dB"
    case medium = "+6 dB"
    case high = "+9 dB"

    var id: String { rawValue }

    var gainDB: Float {
        switch self {
        case .off: return 0
        case .low: return 3
        case .medium: return 6
        case .high: return 9
        }
    }

    var linearGain: Float {
        // Convert dB to linear: gain = 10^(dB/20)
        switch self {
        case .off: return 1.0
        case .low: return 1.413
        case .medium: return 1.995
        case .high: return 2.818
        }
    }
}

// MARK: - AudioEnhancementService

final class AudioEnhancementService: ObservableObject {
    static let shared = AudioEnhancementService()

    // MARK: - Published preferences (persisted)

    @Published var trimSilenceLevel: TrimSilenceLevel {
        didSet {
            UserDefaults.standard.set(trimSilenceLevel.rawValue, forKey: "trimSilenceLevel")
            applyEnhancements()
        }
    }

    @Published var volumeBoostLevel: VolumeBoostLevel {
        didSet {
            UserDefaults.standard.set(volumeBoostLevel.rawValue, forKey: "volumeBoostLevel")
            applyEnhancements()
        }
    }

    @Published private(set) var timeSavedSeconds: TimeInterval = 0

    // MARK: - AVAudioEngine pipeline

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eqNode: AVAudioUnitEQ?
    private var isEngineRunning = false

    private let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "AudioEnhancement")

    var isAnyEnhancementActive: Bool {
        trimSilenceLevel != .off || volumeBoostLevel != .off
    }

    private init() {
        let rawTrim = UserDefaults.standard.string(forKey: "trimSilenceLevel") ?? TrimSilenceLevel.off.rawValue
        let rawBoost = UserDefaults.standard.string(forKey: "volumeBoostLevel") ?? VolumeBoostLevel.off.rawValue
        trimSilenceLevel = TrimSilenceLevel(rawValue: rawTrim) ?? .off
        volumeBoostLevel = VolumeBoostLevel(rawValue: rawBoost) ?? .off
    }

    // MARK: - Engine Setup

    /// Set up AVAudioEngine with the given AVPlayer's output for enhancement.
    /// Call this whenever enhancements are enabled and a new episode begins.
    func setupEngine(with player: AVPlayer?) {
        guard isAnyEnhancementActive else {
            teardownEngine()
            return
        }

        teardownEngine()

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)

        engine.attach(playerNode)
        engine.attach(eq)

        // Configure EQ for volume boost using a global gain shelf
        applyEQSettings(eq)

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = playerNode
            self.eqNode = eq
            isEngineRunning = true
            logger.info("AudioEnhancementEngine started — trim=\(String(self.trimSilenceLevel.rawValue)) boost=\(String(self.volumeBoostLevel.rawValue))")
        } catch {
            logger.error("Failed to start AudioEnhancementEngine: \(error.localizedDescription)")
            teardownEngine()
        }
    }

    func teardownEngine() {
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        eqNode = nil
        isEngineRunning = false
    }

    // MARK: - Apply settings to running engine

    private func applyEnhancements() {
        guard let eq = eqNode else { return }
        if isAnyEnhancementActive {
            applyEQSettings(eq)
        } else {
            teardownEngine()
        }
    }

    private func applyEQSettings(_ eq: AVAudioUnitEQ) {
        // Use globalGain for volume boost (applies to entire EQ unit output)
        eq.globalGain = volumeBoostLevel.gainDB
        // Configure the single band as a low-shelf covering full frequency range
        if let band = eq.bands.first {
            band.filterType = .lowShelf
            band.frequency = 20000
            band.gain = 0
            band.bypass = true
        }
    }

    // MARK: - Trim Silence Analysis

    /// Analyze an audio buffer and return whether it should be skipped (silence).
    /// This is used in an AVAudioEngine tap on the player node.
    func isSilence(buffer: AVAudioPCMBuffer) -> Bool {
        guard trimSilenceLevel != .off else { return false }
        guard let channelData = buffer.floatChannelData else { return false }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return false }

        var sumSquares: Float = 0
        let channel = channelData[0]
        for i in 0..<frameCount {
            sumSquares += channel[i] * channel[i]
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        return rms < trimSilenceLevel.rmsThreshold
    }

    /// Record time saved (called from playback engine when silence is skipped)
    func recordTimeSaved(_ seconds: TimeInterval) {
        DispatchQueue.main.async {
            self.timeSavedSeconds += seconds
        }
    }

    func resetTimeSaved() {
        timeSavedSeconds = 0
    }
}

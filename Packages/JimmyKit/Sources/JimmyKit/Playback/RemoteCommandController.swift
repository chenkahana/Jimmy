#if canImport(MediaPlayer)
import Foundation
import MediaPlayer

/// Wires `MPRemoteCommandCenter` (lock screen, Control Center, CarPlay, headset buttons) to a
/// `Playback`.
public final class RemoteCommandController {
    private weak var playback: Playback?

    /// "Next track" from AirPods, the Lock Screen or CarPlay. The command is off until this is set.
    public var nextTrack: (@MainActor () async -> Void)? {
        didSet { MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = nextTrack != nil }
    }

    /// A speed picked on the Lock Screen. The command is off until this is set.
    public var changeRate: (@MainActor (Float) -> Void)? {
        didSet { MPRemoteCommandCenter.shared().changePlaybackRateCommand.isEnabled = changeRate != nil }
    }

    /// The speeds the Lock Screen offers, matching Now Playing's presets.
    public static let lockScreenRates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    public init(playback: Playback) {
        self.playback = playback
        configure()
    }

    deinit {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackRateCommand.removeTarget(nil)
    }

    /// Call when the user-configured skip intervals change.
    public func updateSkipIntervals(forward: TimeInterval, backward: TimeInterval) {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: forward)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: backward)]
    }

    private func configure() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        // Both off until the app supplies `nextTrack` / `changeRate`.
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = Self.lockScreenRates.map { NSNumber(value: $0) }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in await self?.nextTrack?() }
            return .success
        }

        commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            Task { @MainActor [weak self] in self?.changeRate?(rate) }
            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.playback?.play() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in await self?.playback?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in await self?.playback?.togglePlayPause() }
            return .success
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in await self?.playback?.skipForward() }
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in await self?.playback?.skipBackward() }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let positionTime = event.positionTime
            Task { @MainActor [weak self] in await self?.playback?.seek(to: positionTime) }
            return .success
        }
    }
}
#endif

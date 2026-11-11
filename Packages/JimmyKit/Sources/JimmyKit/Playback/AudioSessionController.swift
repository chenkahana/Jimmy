#if os(iOS)
import Foundation
import AVFoundation

/// Configures the audio session for spoken-word playback and translates `AVAudioSession`
/// notifications into `AudioSessionLogic` events, applying the resulting action to a `Playback`.
/// The decision logic itself lives in `AudioSessionLogic`, which has no `AVAudioSession`
/// dependency and is tested directly.
public final class AudioSessionController {
    private weak var playback: Playback?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    public init(playback: Playback) {
        self.playback = playback
        observe()
    }

    isolated deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    /// Activate the audio session for podcast playback. Call once, e.g. at app launch.
    public func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }

    private func observe() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let event = Self.interruptionEvent(from: notification) else { return }
            let action = AudioSessionLogic.action(for: event)
            Task { @MainActor [weak self] in
                await self?.apply(action)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let event = Self.routeChangeEvent(from: notification)
            let action = AudioSessionLogic.action(for: event)
            Task { @MainActor [weak self] in
                await self?.apply(action)
            }
        }
    }

    private func apply(_ action: AudioSessionLogic.Action) async {
        switch action {
        case .pause: await playback?.pause()
        case .resume: playback?.play()
        case .none: break
        }
    }

    /// Parses an `AVAudioSession.interruptionNotification` into a pure `AudioSessionLogic` event.
    /// `nonisolated` and side-effect free so it can run directly on the notification's delivery
    /// thread, before hopping to the main actor to apply the result.
    nonisolated static func interruptionEvent(from notification: Notification) -> AudioSessionLogic.InterruptionEvent? {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return nil
        }
        switch type {
        case .began:
            return .began
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            return .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    /// Parses an `AVAudioSession.routeChangeNotification` into a pure `AudioSessionLogic` event.
    nonisolated static func routeChangeEvent(from notification: Notification) -> AudioSessionLogic.RouteChangeEvent {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else {
            return .other
        }
        return .oldDeviceUnavailable
    }
}
#endif

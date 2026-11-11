import Foundation

/// Pure decision logic for audio-session interruptions and route changes, kept separate from
/// `AVAudioSession` so it can be unit tested on any host without touching real audio hardware.
/// `AudioSessionController` (iOS-only) translates real `AVAudioSession` notifications into these
/// events and applies the resulting action to a `Playback`.
public nonisolated enum AudioSessionLogic {
    public enum InterruptionEvent: Sendable, Equatable {
        /// Audio was interrupted (phone call, alarm, another app's audio, etc).
        case began
        /// The interruption ended; `shouldResume` reflects the system's `.shouldResume` option.
        case ended(shouldResume: Bool)
    }

    public enum RouteChangeEvent: Sendable, Equatable {
        /// The active output device disappeared (e.g. headphones unplugged).
        case oldDeviceUnavailable
        /// Any other route change (new device available, category change, override, etc).
        case other
    }

    public enum Action: Sendable, Equatable {
        case pause
        case resume
        case none
    }

    /// What to do in response to an interruption.
    public static func action(for event: InterruptionEvent) -> Action {
        switch event {
        case .began:
            return .pause
        case .ended(let shouldResume):
            return shouldResume ? .resume : .none
        }
    }

    /// What to do in response to a route change.
    public static func action(for event: RouteChangeEvent) -> Action {
        switch event {
        case .oldDeviceUnavailable:
            return .pause
        case .other:
            return .none
        }
    }
}

import Foundation
import JimmyKit
import Observation
import WatchConnectivity

/// The watch's live connection to the phone: the latest `WatchSessionState` (`nil` until the
/// phone has sent one, either via `updateApplicationContext` or in reply to `requestState()`),
/// whether the phone is currently reachable, and the one place watch screens send `WatchCommand`s
/// from. No polling — state only changes in response to a `WCSessionDelegate` callback.
@Observable
@MainActor
final class WatchSessionClient: NSObject {
    private(set) var state: WatchSessionState?
    private(set) var isReachable = false

    override init() {
        super.init()
        activateIfSupported()
    }

    /// Sends `command` to the phone. Best-effort: there's no reply, and nothing queues a command
    /// that fails to send — the next tap tries again.
    func send(_ command: WatchCommand) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(command) else { return }
        WCSession.default.sendMessage(["command": data], replyHandler: nil, errorHandler: nil)
    }

    private func activateIfSupported() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Asks the phone for its current state directly, instead of waiting for the next playback or
    /// queue change — so a freshly-launched watch app shows something right away rather than
    /// "Open Jimmy on your iPhone" until the phone next updates.
    private func requestState() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(["request": "state"], replyHandler: { @Sendable [weak self] reply in
            guard let data = reply["state"] as? Data else { return }
            Task { @MainActor in self?.applyEncodedState(data) }
        }, errorHandler: nil)
    }

    private func applyEncodedState(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchSessionState.self, from: data) else { return }
        state = decoded
    }
}

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["state"] as? Data else { return }
        Task { @MainActor in self.applyEncodedState(data) }
    }
}

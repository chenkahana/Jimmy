import Foundation
import JimmyKit
@preconcurrency import WatchConnectivity // replyHandler isn't annotated @Sendable, though WCSession allows calling it from any thread.

/// The phone's one connectivity surface to the watch app: pushes the current `WatchSessionState`
/// (built by `AppModel.watchState()`) via `updateApplicationContext` whenever `AppModel` asks,
/// replies to the watch's own request for that state, and decodes `WatchCommand`s the watch sends
/// back, applying them through `AppModel.apply(_:)`.
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Replaces the watch's whole known state. Safe to call before the watch app has ever
    /// launched or paired — `updateApplicationContext` just queues the latest snapshot for the
    /// next time it's reachable.
    func update(_ state: WatchSessionState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? WCSession.default.updateApplicationContext(["state": data])
    }

    // MARK: - WCSessionDelegate
    // WCSession calls these on its own background queue, so they're nonisolated and hop to the
    // main actor themselves.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["command"] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return }
        Task { @MainActor in
            await AppModel.current?.apply(command)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping @Sendable ([String: Any]) -> Void
    ) {
        guard message["request"] as? String == "state" else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            let state = AppModel.current?.watchState() ?? WatchSessionState()
            let data = (try? JSONEncoder().encode(state)) ?? Data()
            replyHandler(["state": data])
        }
    }
}

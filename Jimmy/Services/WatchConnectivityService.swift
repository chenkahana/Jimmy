import Foundation
import WatchConnectivity

final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func sendPlaybackUpdate(episode: Episode?, isPlaying: Bool, position: TimeInterval, duration: TimeInterval) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }

        var payload: [String: Any] = [
            "isPlaying": isPlaying,
            "position": position,
            "duration": duration
        ]

        if let episode = episode, let data = try? JSONEncoder().encode(episode) {
            payload["episode"] = data
        }

        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        guard let command = message["command"] as? String else { return }
        DispatchQueue.main.async {
            switch command {
            case "playPause":
                AudioPlayerService.shared.togglePlayPause()
            case "seekForward":
                AudioPlayerService.shared.seekForward()
            case "seekBackward":
                AudioPlayerService.shared.seekBackward()
            default:
                break
            }
        }
    }
}

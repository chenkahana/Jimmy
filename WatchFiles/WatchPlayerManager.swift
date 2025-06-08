import Foundation
import Combine
import WatchConnectivity

final class WatchPlayerManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchPlayerManager()

    @Published var currentEpisode: Episode?
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - Playback Commands
    func playPause() {
        sendCommand("playPause")
    }

    func seekBackward() {
        sendCommand("seekBackward")
    }

    func seekForward() {
        sendCommand("seekForward")
    }

    private func sendCommand(_ command: String) {
        let message = ["command": command]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            if let data = message["episode"] as? Data {
                self.currentEpisode = try? JSONDecoder().decode(Episode.self, from: data)
            }
            if let playing = message["isPlaying"] as? Bool { self.isPlaying = playing }
            if let pos = message["position"] as? Double { self.playbackPosition = pos }
            if let dur = message["duration"] as? Double { self.duration = dur }
        }
    }
}

import Foundation
import Combine

final class WatchPlayerManager: ObservableObject {
    static let shared = WatchPlayerManager()

    @Published var currentEpisode: Episode?
    @Published var isPlaying: Bool = false

    private init() {
        // TODO: Connect to iPhone app using WatchConnectivity
    }

    func playPause() {
        // TODO: Implement play/pause communication
    }

    func seekBackward() {
        // TODO: Seek backward 15 seconds
    }

    func seekForward() {
        // TODO: Seek forward 15 seconds
    }
}

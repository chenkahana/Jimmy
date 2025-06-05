import Foundation
import CarPlay
import MediaPlayer

final class CarPlayManager: NSObject {
    static let shared = CarPlayManager()

    private var interfaceController: CPInterfaceController?

    private override init() {
        super.init()
    }

    func connect(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        MPPlayableContentManager.shared().delegate = self
        MPPlayableContentManager.shared().dataSource = self
        interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: false)
    }

    func disconnect() {
        interfaceController = nil
        MPPlayableContentManager.shared().delegate = nil
        MPPlayableContentManager.shared().dataSource = nil
    }

    func reloadData() {
        MPPlayableContentManager.shared().reloadData()
    }

    /// Helper to retrieve the podcast associated with an episode
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
}

extension CarPlayManager: MPPlayableContentDelegate {
    func playableContentManager(_ contentManager: MPPlayableContentManager, initiatePlaybackOf item: MPContentItem, completionHandler: @escaping (Error?) -> Void) {
        guard let uuid = UUID(uuidString: item.identifier),
              let episode = QueueViewModel.shared.queue.first(where: { $0.id == uuid }) else {
            completionHandler(NSError(domain: "Jimmy", code: 0))
            return
        }
        QueueViewModel.shared.playEpisodeFromQueue(episode)
        completionHandler(nil)
    }
}

extension CarPlayManager: MPPlayableContentDataSource {
    func numberOfChildItems(at indexPath: IndexPath) -> Int {
        if indexPath.isEmpty { return 1 }
        return QueueViewModel.shared.queue.count
    }

    func contentItem(at indexPath: IndexPath) -> MPContentItem? {
        if indexPath.isEmpty {
            let item = MPContentItem(identifier: "queueRoot")
            item.title = "Queue"
            item.isContainer = true
            return item
        } else {
            let episode = QueueViewModel.shared.queue[indexPath[1]]
            let item = MPContentItem(identifier: episode.id.uuidString)
            item.title = episode.title
            item.subtitle = getPodcast(for: episode)?.title
            item.isContainer = false
            item.isPlayable = true
            return item
        }
    }
}

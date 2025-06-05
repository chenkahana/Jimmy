import Foundation
import CarPlay

final class CarPlayManager: NSObject {
    static let shared = CarPlayManager()

    private var interfaceController: CPInterfaceController?
    private var queueTemplate: CPListTemplate?

    private override init() {
        super.init()
    }

    func connect(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        queueTemplate = buildQueueTemplate()
        if let template = queueTemplate {
            interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: false)
            interfaceController.pushTemplate(template, animated: false)
        }
    }

    func disconnect() {
        interfaceController = nil
        queueTemplate = nil
    }

    func reloadData() {
        guard let controller = interfaceController else { return }
        queueTemplate = buildQueueTemplate()
        if let template = queueTemplate {
            controller.setRootTemplate(CPNowPlayingTemplate.shared, animated: false)
            controller.pushTemplate(template, animated: false)
        }
    }

    /// Helper to retrieve the podcast associated with an episode
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }

    private func queueSection() -> CPListSection {
        let items = QueueViewModel.shared.queue.map { episode -> CPListItem in
            let item = CPListItem(text: episode.title,
                                 detailText: getPodcast(for: episode)?.title ?? "")
            item.handler = { _, completion in
                QueueViewModel.shared.playEpisodeFromQueue(episode)
                completion()
            }
            return item
        }
        return CPListSection(items: items)
    }

    private func buildQueueTemplate() -> CPListTemplate {
        let section = queueSection()
        let template = CPListTemplate(title: "Queue", sections: [section])
        return template
    }
}


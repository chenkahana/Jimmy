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
        
        // Only rebuild template if queue contents have actually changed
        let newTemplate = buildQueueTemplate()
        
        // Compare with existing template to avoid unnecessary updates
        if let existingTemplate = queueTemplate,
           existingTemplate.sections.count == newTemplate.sections.count,
           let existingItems = existingTemplate.sections.first?.items,
           let newItems = newTemplate.sections.first?.items,
           existingItems.count == newItems.count {
            
            // Check if the items are actually different - cast to CPListItem for comparison
            let itemsChanged = zip(existingItems, newItems).contains { existing, new in
                guard let existingItem = existing as? CPListItem,
                      let newItem = new as? CPListItem else { return true }
                return existingItem.text != newItem.text || existingItem.detailText != newItem.detailText
            }
            
            if !itemsChanged {
                return // No changes needed
            }
        }
        
        queueTemplate = newTemplate
        
        // Update templates more efficiently
        if controller.templates.count > 1 {
            controller.popToRootTemplate(animated: false)
        }
        
        controller.pushTemplate(newTemplate, animated: false)
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


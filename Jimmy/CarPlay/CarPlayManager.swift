import Foundation
import CarPlay

final class CarPlayManager: NSObject {
    static let shared = CarPlayManager()

    private var interfaceController: CPInterfaceController?
    private var queueTemplate: CPListTemplate?
    private let queue = DispatchQueue(label: "com.jimmy.carplay", qos: .userInteractive)

    private override init() {
        super.init()
    }

    func connect(interfaceController: CPInterfaceController, window: CPWindow) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.interfaceController = interfaceController
            
            // Build initial template safely
            let initialTemplate = self.buildQueueTemplate()
            
            DispatchQueue.main.async {
                // Set root template first
                interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: false) { [weak self] success, error in
                    if let error = error {
                        print("CarPlay: Failed to set root template: \(error)")
                        return
                    }
                    
                    // Then push the queue template
                    interfaceController.pushTemplate(initialTemplate, animated: false) { success, error in
                        if let error = error {
                            print("CarPlay: Failed to push queue template: \(error)")
                        } else {
                            self?.queueTemplate = initialTemplate
                        }
                    }
                }
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.interfaceController = nil
            self?.queueTemplate = nil
        }
    }

    func reloadData() {
        queue.async { [weak self] in
            guard let self = self,
                  let controller = self.interfaceController else { return }
            
            // Only rebuild template if queue contents have actually changed
            let newTemplate = self.buildQueueTemplate()
            
            // Compare with existing template to avoid unnecessary updates
            if let existingTemplate = self.queueTemplate,
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
            
            DispatchQueue.main.async {
                // Update templates more safely
                if controller.templates.count > 1 {
                    controller.popToRootTemplate(animated: false) { [weak self] success, error in
                        if let error = error {
                            print("CarPlay: Failed to pop to root: \(error)")
                            return
                        }
                        
                        controller.pushTemplate(newTemplate, animated: false) { success, error in
                            if let error = error {
                                print("CarPlay: Failed to push updated template: \(error)")
                            } else {
                                self?.queueTemplate = newTemplate
                            }
                        }
                    }
                } else {
                    controller.pushTemplate(newTemplate, animated: false) { [weak self] success, error in
                        if let error = error {
                            print("CarPlay: Failed to push template: \(error)")
                        } else {
                            self?.queueTemplate = newTemplate
                        }
                    }
                }
            }
        }
    }

    /// Helper to retrieve the podcast associated with an episode
    private func getPodcast(for episode: Episode) -> Podcast? {
        // Safely access PodcastService on main thread
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
            }
        }
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }

    private func queueSection() -> CPListSection {
        // Safely access queue data
        let queueData = DispatchQueue.main.sync {
            return QueueViewModel.shared.queue
        }
        
        let items = queueData.compactMap { episode -> CPListItem? in
            // Ensure we have a valid episode title
            guard !episode.title.isEmpty else {
                return nil
            }
            
            let podcastTitle = getPodcast(for: episode)?.title ?? "Unknown Podcast"
            let item = CPListItem(text: episode.title, detailText: podcastTitle)
            
            item.handler = { [weak self] _, completion in
                // Safely execute on main thread
                DispatchQueue.main.async {
                    QueueViewModel.shared.playEpisodeFromQueue(episode)
                    completion()
                }
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


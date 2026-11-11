import Foundation
import CarPlay
import os

/// Manages CarPlay interface with a tab bar template: Library, Queue, Now Playing
final class CarPlayManager: NSObject {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "CarPlayManager")
    static let shared = CarPlayManager()

    private var interfaceController: CPInterfaceController?
    private let queue = DispatchQueue(label: "com.jimmy.carplay", qos: .userInteractive)

    private override init() {
        super.init()
    }

    // MARK: - Connection Lifecycle

    func connect(interfaceController: CPInterfaceController, window: CPWindow) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.interfaceController = interfaceController

            DispatchQueue.main.async {
                Task { @MainActor in
                    let tabBar = await self.buildTabBarTemplate()
                    interfaceController.setRootTemplate(tabBar, animated: false) { _, error in
                        if let error = error {
                            Self.logger.error("CarPlay: Failed to set root template: \(error)")
                        }
                    }
                }
            }
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            self?.interfaceController = nil
        }
    }

    func reloadData() {
        queue.async { [weak self] in
            guard let self = self,
                  let controller = self.interfaceController else { return }

            DispatchQueue.main.async {
                Task { @MainActor in
                    let tabBar = await self.buildTabBarTemplate()
                    controller.setRootTemplate(tabBar, animated: false) { _, error in
                        if let error = error {
                            Self.logger.error("CarPlay: Failed to reload template: \(error)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab Bar Template

    @MainActor
    private func buildTabBarTemplate() async -> CPTabBarTemplate {
        let libraryTab = await buildLibraryTemplate()
        let queueTab = await buildQueueTemplate()
        let nowPlayingTab = CPNowPlayingTemplate.shared

        // Add playback speed button to Now Playing
        let speedButton = CPNowPlayingPlaybackRateButton { [weak self] _ in
            Task { @MainActor in
                self?.cyclePlaybackSpeed()
            }
        }
        nowPlayingTab.updateNowPlayingButtons([speedButton])

        let tabBar = CPTabBarTemplate(templates: [libraryTab, queueTab, nowPlayingTab])
        return tabBar
    }

    // MARK: - Library Tab

    @MainActor
    private func buildLibraryTemplate() async -> CPListTemplate {
        let podcasts = (AppModel.current?.podcasts.map { $0.asLegacyPodcast() } ?? [])

        let items: [CPListItem] = podcasts.map { podcast in
            let item = CPListItem(text: podcast.cleanTitle, detailText: podcast.author)

            // Load artwork if available
            if let artworkURL = podcast.artworkURL {
                Task {
                    if let data = try? Data(contentsOf: artworkURL),
                       let image = UIImage(data: data) {
                        item.setImage(image)
                    }
                }
            }

            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.showEpisodesForPodcast(podcast)
                }
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabImage = UIImage(systemName: "music.note.list")
        return template
    }

    @MainActor
    private func showEpisodesForPodcast(_ podcast: Podcast) async {
        guard let controller = interfaceController else { return }

        let episodes = await getEpisodesForPodcast(podcast)
        let items: [CPListItem] = episodes.prefix(20).map { episode in
            let detail = episode.formattedDuration
            let item = CPListItem(text: episode.title, detailText: detail)
            item.handler = { _, completion in
                Task { @MainActor in
                    await AppModel.current?.play(episode.asPlaybackEpisode())
                }
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: podcast.cleanTitle, sections: [section])
        controller.pushTemplate(template, animated: true, completion: nil)
    }

    @MainActor
    private func getEpisodesForPodcast(_ podcast: Podcast) async -> [Episode] {
        do {
            let repository = DIContainer.shared.episodeRepository
            let episodesWithState = try await repository.fetchEpisodes(for: podcast.id, ignoreCache: false)
            return episodesWithState.map { $0.episode }
        } catch {
            return []
        }
    }

    // MARK: - Queue Tab

    @MainActor
    private func buildQueueTemplate() async -> CPListTemplate {
        let queueData = await AppModel.current?.resolveQueueEpisodes() ?? []
        let podcasts = (AppModel.current?.podcasts.map { $0.asLegacyPodcast() } ?? [])

        let items = queueData.compactMap { episode -> CPListItem? in
            guard !episode.title.isEmpty else { return nil }

            let podcastTitle = podcasts.first { $0.id == episode.podcastID }?.title ?? ""
            let item = CPListItem(text: episode.title, detailText: podcastTitle)

            item.handler = { _, completion in
                Task { @MainActor in
                    await AppModel.current?.play(episode.asPlaybackEpisode())
                }
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Queue", sections: [section])
        template.tabImage = UIImage(systemName: "list.bullet")
        return template
    }

    // MARK: - Playback Speed

    @MainActor
    private func cyclePlaybackSpeed() {
        guard let playback = AppModel.current?.playback else { return }
        let speeds: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75]
        let currentIndex = speeds.firstIndex(of: playback.rate) ?? 0
        let nextIndex = (currentIndex + 1) % speeds.count
        playback.setRate(speeds[nextIndex])
    }

    // MARK: - Helpers

    @MainActor
    private func getPodcast(for episode: Episode) -> Podcast? {
        return (AppModel.current?.podcasts.map { $0.asLegacyPodcast() } ?? []).first { $0.id == episode.podcastID }
    }
}

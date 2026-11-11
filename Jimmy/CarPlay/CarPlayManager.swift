import CarPlay
import Foundation
import JimmyKit
import Observation
import UIKit

/// CarPlay's three templates — Queue, Library, and the system Now Playing template — read and
/// write through `AppModel` alone: no `DIContainer`, no `NotificationCenter`, no polling timer.
/// `withObservationTracking` loops re-register themselves on every change to `queue`/`podcasts`
/// (rebuilding the Queue and Library rows) and to `playback` (refreshing which row, if any, shows
/// the "now playing" indicator).
@MainActor
final class CarPlayManager: NSObject {
    static let shared = CarPlayManager()

    /// A podcast's episode list, currently pushed onto the interface controller's stack — kept
    /// around so a `playback` change can refresh its rows' "now playing" indicator without
    /// re-reading the store. Cleared once the user navigates back past it.
    private struct PushedEpisodeList {
        let template: CPListTemplate
        let rows: [AppModel.CarPlayEpisodeRow]
    }

    private var interfaceController: CPInterfaceController?
    private let queueTemplate: CPListTemplate = {
        let template = CPListTemplate(title: "Queue", sections: [])
        template.tabImage = UIImage(systemName: "list.bullet")
        return template
    }()
    private let libraryTemplate: CPListTemplate = {
        let template = CPListTemplate(title: "Library", sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")
        return template
    }()
    private var pushedEpisodeList: PushedEpisodeList?

    private override init() {
        super.init()
    }

    // MARK: - Connection lifecycle

    func connect(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let tabBar = CPTabBarTemplate(templates: [queueTemplate, libraryTemplate, CPNowPlayingTemplate.shared])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
        refreshQueueTemplate()
        refreshLibraryTemplate()
        observeQueueAndLibrary()
        observePlayback()
    }

    func disconnect() {
        interfaceController = nil
        pushedEpisodeList = nil
    }

    // MARK: - Queue tab

    private func refreshQueueTemplate() {
        let rows = AppModel.current?.carPlayQueueRows ?? []
        queueTemplate.updateSections([listSection(for: rows)])
    }

    // MARK: - Library tab

    private func refreshLibraryTemplate() {
        let rows = AppModel.current?.carPlayLibraryRows ?? []
        let items = rows.map { row -> CPListItem in
            let item = CPListItem(text: row.title, detailText: row.subtitle)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    await self?.pushEpisodeList(for: row.podcast)
                    completion()
                }
            }
            return item
        }
        libraryTemplate.updateSections([CPListSection(items: items)])
    }

    private func pushEpisodeList(for podcast: JimmyKit.Podcast) async {
        guard let interfaceController, let appModel = AppModel.current else { return }
        let rows = await appModel.carPlayEpisodeRows(podcastID: podcast.id)
        let template = CPListTemplate(title: podcast.title, sections: [listSection(for: rows)])
        pushedEpisodeList = PushedEpisodeList(template: template, rows: rows)
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// Refreshes the pushed podcast-episode list's "now playing" indicator. A no-op once the user
    /// has navigated back past it (its template is no longer on the interface controller's stack).
    private func refreshPushedEpisodeList() {
        guard let pushedEpisodeList else { return }
        guard interfaceController?.templates.contains(where: { $0 === pushedEpisodeList.template }) == true else {
            self.pushedEpisodeList = nil
            return
        }
        pushedEpisodeList.template.updateSections([listSection(for: pushedEpisodeList.rows)])
    }

    // MARK: - Shared row building

    /// Builds one section of episode rows: tapping a row plays it, through `AppModel.play(_:)`
    /// (which also moves it to the front of the queue — the same write every other "tap to play"
    /// in the app goes through). The row currently playing, if any, shows CarPlay's "now playing"
    /// indicator.
    private func listSection(for rows: [AppModel.CarPlayEpisodeRow]) -> CPListSection {
        let nowPlayingEpisodeID = currentlyPlayingEpisodeID()
        let items = rows.map { row -> CPListItem in
            let item = CPListItem(text: row.title, detailText: row.subtitle)
            item.isPlaying = row.episode.id == nowPlayingEpisodeID
            item.handler = { _, completion in
                Task { @MainActor in
                    await AppModel.current?.play(row.episode)
                    completion()
                }
            }
            return item
        }
        return CPListSection(items: items)
    }

    private func currentlyPlayingEpisodeID() -> UUID? {
        guard let playback = AppModel.current?.playback, playback.isPlaying else { return nil }
        return playback.currentEpisode?.id
    }

    // MARK: - Observation

    private func observeQueueAndLibrary() {
        withObservationTracking { [weak self] in
            _ = AppModel.current?.queue
            _ = AppModel.current?.podcasts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.interfaceController != nil else { return }
                self.refreshQueueTemplate()
                self.refreshLibraryTemplate()
                self.observeQueueAndLibrary()
            }
        }
    }

    private func observePlayback() {
        withObservationTracking { [weak self] in
            _ = AppModel.current?.playback?.currentEpisode
            _ = AppModel.current?.playback?.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.interfaceController != nil else { return }
                self.refreshQueueTemplate()
                self.refreshPushedEpisodeList()
                self.observePlayback()
            }
        }
    }
}

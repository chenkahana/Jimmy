import Foundation
import JimmyKit
import Observation
import os

/// Runs one import end to end and reports it as it goes: finds each show's feed, subscribes
/// (six at a time), then writes played state and progress and fills the Queue with what the
/// listener was in the middle of. The onboarding screens and Settings both drive this.
@Observable
@MainActor
final class LibraryImportSession {
    enum Phase: Equatable {
        case idle
        case reading
        case addingShows
        case importingHistory
        case finished
        case failed(String)
    }

    struct ShowRow: Identifiable, Equatable {
        let id: Int
        var title: String
        var artworkURL: URL?
        var state: ImportShowState
    }

    private(set) var phase: Phase = .idle
    private(set) var rows: [ShowRow] = []
    private(set) var playedCount = 0
    private(set) var inProgressCount = 0
    private(set) var queuedCount = 0

    var addedCount: Int { rows.count { $0.state == .added } }
    var notFoundCount: Int { rows.count { $0.state == .notFound } }
    var doneCount: Int { rows.count { $0.state == .added || $0.state == .notFound } }
    var isRunning: Bool { [.reading, .addingShows, .importingHistory].contains(phase) }

    /// How many in-progress or saved episodes go to the Queue at most.
    static let queueLimit = 10
    private static let concurrentShows = 6
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "LibraryImport")

    private let directory = PodcastDirectory()

    /// Reads and imports the files a listener picked or shared (several at once for Spotify's
    /// data download).
    func run(files: [URL], model: AppModel) async {
        phase = .reading
        var combined = ImportResult(feeds: [], skipped: [])
        var unreadable = 0
        for file in files {
            let hasAccess = file.startAccessingSecurityScopedResource()
            defer { if hasAccess { file.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: file), let result = try? ImportFile.parse(data: data) else {
                unreadable += 1
                continue
            }
            combined = combined.merged(with: result)
        }
        if combined.isEmpty {
            phase = .failed(unreadable > 0
                ? "Jimmy couldn't read that file. Choose an OPML file or your app's export."
                : "That file has no shows in it.")
            return
        }
        await run(combined, model: model)
    }

    /// Imports whatever `fetch` returns (Spotify's library, after sign-in), reading meanwhile.
    func run(fetching fetch: () async throws -> ImportResult, model: AppModel) async {
        phase = .reading
        do {
            let result = try await fetch()
            guard !result.isEmpty else {
                phase = .failed("There are no saved shows in that account.")
                return
            }
            await run(result, model: model)
        } catch {
            phase = .failed("Couldn't reach Spotify. Check your connection and try again.")
        }
    }

    /// Imports feed and show links pasted from Shortcuts, Apple Podcasts or anywhere else.
    func run(pastedText: String, model: AppModel) async {
        let result = LinkTextParser.parse(pastedText)
        guard !result.isEmpty else {
            phase = .failed("There are no show links on the clipboard.")
            return
        }
        await run(result, model: model)
    }

    func run(_ result: ImportResult, model: AppModel) async {
        let pending = makePending(result)
        rows = pending.map { ShowRow(id: $0.id, title: $0.displayTitle, artworkURL: nil, state: .waiting) }
        playedCount = 0
        inProgressCount = 0
        queuedCount = 0
        phase = .addingShows

        let podcastIDs = await addShows(pending, model: model)
        phase = .importingHistory
        await importHistory(result.history, podcastIDs: podcastIDs, model: model)
        phase = .finished
        Self.logger.info("Import: \(self.addedCount) added, \(self.notFoundCount) not found")
        Self.logger.info("Import: \(self.playedCount) played, \(self.queuedCount) queued")
    }

    // MARK: - Shows

    private struct PendingShow: Sendable {
        let id: Int
        let source: PendingShowSource

        var displayTitle: String {
            switch source {
            case .link(let feed):
                feed.title ?? Self.slugTitle(feed.feedURL) ?? feed.feedURL.host ?? feed.feedURL.absoluteString
            case .name(let name): name.title
            }
        }

        /// "The Daily" from `podcasts.apple.com/us/podcast/the-daily/id1200361736`, until the
        /// directory answers with the real title.
        static func slugTitle(_ url: URL) -> String? {
            guard case .apple = ShowLink(url), url.pathComponents.count >= 2 else { return nil }
            let slug = url.pathComponents[url.pathComponents.count - 2]
            guard slug != "podcast" else { return nil }
            return slug.replacingOccurrences(of: "-", with: " ").capitalized
        }

        /// Keys history entries use to find this show: its feed URL or its name.
        var keys: [String] {
            switch source {
            case .link(let feed):
                [FeedURLNormalizer.key(for: feed.feedURL)] + (feed.title.map { [TitleNormalizer.key($0)] } ?? [])
            case .name(let name): [TitleNormalizer.key(name.title)]
            }
        }
    }

    private func makePending(_ result: ImportResult) -> [PendingShow] {
        let links = result.feeds.map(PendingShowSource.link)
        let names = result.showNames.map(PendingShowSource.name)
        return (links + names).enumerated().map { PendingShow(id: $0.offset, source: $0.element) }
    }

    /// Subscribes to every pending show, a few at a time, and returns which podcast each history
    /// key now points at.
    private func addShows(_ pending: [PendingShow], model: AppModel) async -> [String: UUID] {
        var podcastIDs: [String: UUID] = [:]

        await withTaskGroup(of: (PendingShow, JimmyKit.Podcast?).self) { group in
            var nextIndex = 0
            var running = 0
            while nextIndex < pending.count || running > 0 {
                while nextIndex < pending.count, running < Self.concurrentShows {
                    let show = pending[nextIndex]
                    nextIndex += 1
                    running += 1
                    setState(.adding, for: show.id)
                    group.addTask { await self.subscribe(show, model: model) }
                }
                guard let (show, podcast) = await group.next() else { break }
                running -= 1
                if let podcast, let index = rows.firstIndex(where: { $0.id == show.id }) {
                    rows[index].title = podcast.title
                    rows[index].artworkURL = podcast.artworkURL
                    rows[index].state = .added
                    let podcastKeys = [TitleNormalizer.key(podcast.title), FeedURLNormalizer.key(for: podcast.feedURL)]
                    for key in show.keys + podcastKeys {
                        podcastIDs[key] = podcast.id
                    }
                } else {
                    setState(.notFound, for: show.id)
                }
            }
        }
        return podcastIDs
    }

    private func setState(_ state: ImportShowState, for id: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].state = state
    }

    private func subscribe(_ show: PendingShow, model: AppModel) async -> (PendingShow, JimmyKit.Podcast?) {
        guard let feedURL = await resolveFeedURL(show) else { return (show, nil) }
        do {
            return (show, try await model.subscribe(feedURL: feedURL))
        } catch {
            Self.logger.error("Couldn't add \(feedURL.absoluteString): \(error.localizedDescription)")
            return (show, nil)
        }
    }

    /// The RSS feed behind a pending show: the link itself, an Apple Podcasts id looked up in
    /// the directory, or a name (from Spotify) searched for.
    private func resolveFeedURL(_ show: PendingShow) async -> URL? {
        switch show.source {
        case .name(let name):
            return await search(name)
        case .link(let feed):
            switch ShowLink(feed.feedURL) {
            case .feed(let url):
                return url
            case .apple(let id):
                if let url = try? await directory.lookup(ids: [id]).first?.feedURL { return url }
                return await feed.title.asyncFlatMap { await self.search(ImportedShowName(title: $0, publisher: nil)) }
            case .spotify(let url):
                guard let title = await Self.spotifyShowTitle(url) ?? feed.title else { return nil }
                return await search(ImportedShowName(title: title, publisher: nil))
            }
        }
    }

    private func search(_ name: ImportedShowName) async -> URL? {
        let results = (try? await directory.search(query: name.title)) ?? []
        return DirectoryMatcher.bestMatch(for: name, in: results)?.feedURL
    }

    /// A Spotify show link's title, from Spotify's public oEmbed endpoint (no sign-in).
    private static func spotifyShowTitle(_ url: URL) async -> String? {
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let endpoint = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: endpoint) else { return nil }
        struct OEmbed: Decodable { let title: String }
        return try? JSONDecoder().decode(OEmbed.self, from: data).title
    }

    // MARK: - History

    private func importHistory(_ history: [ImportedEpisodeState], podcastIDs: [String: UUID], model: AppModel) async {
        guard let store = model.readyStore, !history.isEmpty else { return }

        var statesByPodcast: [UUID: [ImportedEpisodeState]] = [:]
        for state in history {
            let key = state.feedURL.map { FeedURLNormalizer.key(for: $0) }
                ?? state.podcastTitle.map(TitleNormalizer.key)
            guard let key, let podcastID = podcastIDs[key] else { continue }
            statesByPodcast[podcastID, default: []].append(state)
        }

        var queue: [QueueCandidate] = []
        for (podcastID, states) in statesByPodcast {
            let episodes = (try? await store.episodes(podcastID: podcastID)) ?? []
            let plan = HistoryPlan.make(states: states, episodes: episodes)
            for action in plan.actions {
                switch action {
                case .markPlayed(let id): try? await store.markPlayed(id)
                case .saveProgress(let progress): try? await store.saveProgress(progress)
                }
            }
            playedCount += plan.playedCount
            inProgressCount += plan.inProgressCount
            queue += plan.queue
        }

        let mostRecent = queue.sorted { $0.date > $1.date }.prefix(Self.queueLimit)
        for candidate in mostRecent where !model.isQueued(candidate.episodeID) {
            await model.enqueue(candidate.episodeID)
            queuedCount += 1
        }
    }
}

/// Where one show in an import stands.
enum ImportShowState: Equatable { case waiting, adding, added, notFound }

/// A show as the import found it: a link (feed, Apple Podcasts or Spotify page) or only a name.
private enum PendingShowSource: Sendable {
    case link(ImportedFeed)
    case name(ImportedShowName)
}

private extension Optional {
    func asyncFlatMap<U>(_ transform: (Wrapped) async -> U?) async -> U? {
        guard let self else { return nil }
        return await transform(self)
    }
}

import Foundation
import MediaPlayer
import Observation
import JimmyKit

/// Owns the one JimmyKit `Store` every screen will eventually read and write through, and the
/// `Playback` object built on top of it — the one player now, driving the audio session, remote
/// commands and Now Playing through `Ready`'s controllers. Opened synchronously, before any old
/// service (`DatabaseManager`, `DIContainer`, ...) touches the same file — see `JimmyApp.init()`.
///
/// Screens still run on the old services until they move onto `JimmyKit` one at a time in later
/// PRs, so nothing reads from `store` yet except through the compatibility helpers below.
///
/// `Downloads` joins `AppModel` in the PR that deletes `DownloadManager`: JimmyKit's `Downloads`
/// uses the same background `URLSession` identifier as `DownloadManager`
/// (`com.chenkahana.Jimmy.downloads`), and a process can't run two sessions on one identifier.
@Observable
@MainActor
final class AppModel {
    /// Whether opening the store succeeded. There's no "still opening" case: `Store.init` is
    /// synchronous, so this is known by the time anything can observe `launchState`.
    enum LaunchState {
        case ready(Ready)
        case failed(Failure)
    }

    struct Ready {
        let store: Store
        let playback: Playback
        let audioSession: AudioSessionController
        let remoteCommands: RemoteCommandController
        let nowPlaying: NowPlayingController
    }

    struct Failure {
        /// Description of the error `Store.init` threw, shown as-is on the launch failure screen.
        let message: String
    }

    private(set) var launchState: LaunchState

    /// The queue's episodes, in play order — kept current by `store.observeQueue()`. Empty
    /// (rather than stale) whenever `launchState` isn't `.ready`.
    private(set) var queue: [JimmyKit.Episode] = []
    private var queueObservationTask: Task<Void, Never>?

    /// The subscribed podcasts, kept current by `store.observePodcasts()` — see
    /// `AppModel+Library.swift`. Empty (rather than stale) whenever `launchState` isn't `.ready`.
    private(set) var podcasts: [JimmyKit.Podcast] = []
    private var podcastsObservationTask: Task<Void, Never>?

    /// The most recent `refreshAll()`/`refresh(_:)` failures, keyed by podcast id, for the
    /// Library screen to show. A podcast absent from this dictionary either refreshed
    /// successfully last time or hasn't been refreshed yet this launch. Written from
    /// `AppModel+Library.swift`, so this can't be `private(set)` (that's file-scoped, not
    /// type-scoped) — every other `AppModel+*.swift` extension can set it too, by convention only.
    var lastRefreshErrors: [UUID: String] = [:]

    private let databasePath: String
    private let legacyInput: () -> LegacyInput?

    // MARK: - Playback side-effect bookkeeping (see AppModel+Playback.swift)

    /// Avoids restarting `ListeningStatsService`'s tracking timer on every unrelated playback
    /// state change (duration/rate ticks) — only when `isPlaying` itself actually flips.
    var lastObservedIsPlaying = false
    /// Avoids rewriting `lastPlayingEpisodeID` on every tick — only when the episode changes.
    var lastObservedEpisodeID: UUID?
    /// Now Playing artwork, fetched once per episode id and reused across position/rate updates.
    var nowPlayingArtworkCache: [UUID: MPMediaItemArtwork] = [:]
    /// Up to `WatchSessionState.maxRecentCount` distinct episodes that started playing this
    /// session, most-recent-first — mirrored to the watch as "Recent" (see
    /// `AppModel+WatchSession.swift`). Not persisted: starts empty each launch.
    var recentlyPlayedEpisodes: [JimmyKit.Episode] = []

    /// Old singletons that can't read the environment (episode rows, `ShakeUndoManager`,
    /// `AppDataDocument`'s iCloud sync, ...) reach the queue and `playback` through this until
    /// they're deleted in later PRs. `WatchConnectivityService` and `CarPlayManager` reach it the
    /// same way, permanently — both are session/scene delegates with no SwiftUI environment of
    /// their own to read from. Set once, in `JimmyApp.init()`.
    static weak var current: AppModel?

    /// Fetches feeds for `subscribe(feedURL:)`/`refreshAll()`/`refresh(_:)` — see
    /// `AppModel+Library.swift`. Injectable so tests can pass one built on a stubbed
    /// `URLSession` instead of hitting the network.
    let feedFetcher: FeedFetcher

    init(
        databasePath: String,
        legacyInput: @escaping () -> LegacyInput? = { nil },
        feedFetcher: FeedFetcher = FeedFetcher()
    ) {
        self.databasePath = databasePath
        self.legacyInput = legacyInput
        self.feedFetcher = feedFetcher
        self.launchState = Self.open(databasePath: databasePath, legacyInput: legacyInput())
        startObservingQueueIfReady()
        startObservingPodcastsIfReady()
        startObservingPlaybackIfReady()
    }

    /// Tries opening the store again at the same path, e.g. after the user tapped "Try Again".
    func retry() {
        launchState = Self.open(databasePath: databasePath, legacyInput: legacyInput())
        startObservingQueueIfReady()
        startObservingPodcastsIfReady()
        startObservingPlaybackIfReady()
    }

    private func startObservingQueueIfReady() {
        queueObservationTask?.cancel()
        queueObservationTask = nil
        queue = []

        guard case .ready(let ready) = launchState else { return }
        let store = ready.store
        queueObservationTask = Task { [weak self] in
            do {
                for try await episodes in store.observeQueue() {
                    guard let self, !Task.isCancelled else { return }
                    self.queue = episodes
                    self.pushWatchState()
                }
            } catch {
                // The observation stopped (e.g. the store closed); the queue just stops updating.
            }
        }
    }

    private func startObservingPodcastsIfReady() {
        podcastsObservationTask?.cancel()
        podcastsObservationTask = nil
        podcasts = []

        guard case .ready(let ready) = launchState else { return }
        let store = ready.store
        podcastsObservationTask = Task { [weak self] in
            do {
                for try await podcasts in store.observePodcasts() {
                    guard let self, !Task.isCancelled else { return }
                    self.podcasts = podcasts
                }
            } catch {
                // The observation stopped (e.g. the store closed); podcasts just stop updating.
            }
        }
    }

    /// Moves `jimmy.db` and its `-wal`/`-shm` files aside (to `<name>.broken-<timestamp>`, in the
    /// same folder — never deleted, so the library can still be recovered later) and tries
    /// opening a fresh store at the same path.
    func resetLibrary() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = databasePath + suffix
            guard fileManager.fileExists(atPath: source) else { continue }
            try? fileManager.moveItem(atPath: source, toPath: source + ".broken-\(timestamp)")
        }
        retry()
    }

    private static func open(databasePath: String, legacyInput: LegacyInput?) -> LaunchState {
        do {
            let store = try Store(path: databasePath, legacy: legacyInput)
            let playback = Playback(
                engine: AVPlayerEngine(),
                // Mirrors every save into the legacy columns Library/PodcastDetail/episode rows
                // still read, until PR 18 moves them onto `progress` directly.
                progressStore: LegacyProgressMirror(store: store),
                // Posts `.episodeRemovedFromQueue` on auto-advance too, not just a user-initiated
                // `AppModel.dequeue` — see `NotifyingQueueSource`.
                queueSource: NotifyingQueueSource(store: store)
            )
            // A downloaded episode plays from disk no matter how playback reaches it — a direct
            // `AppModel.play`, auto-advance, or the remote "next track" command.
            playback.resolveAudioURL = { episode in
                DownloadManager.shared.effectiveURL(forEpisodeID: episode.id, remoteURL: episode.audioURL)
            }
            let audioSession = AudioSessionController(playback: playback)
            // Activated once, here, rather than reactively the first time `playback.isPlaying`
            // flips: that happens after the engine has already started playing, so the very first
            // play right after launch (or one CarPlay/background initiates) could begin under
            // whatever category the session defaulted to.
            try? audioSession.activate()
            return .ready(Ready(
                store: store,
                playback: playback,
                audioSession: audioSession,
                remoteCommands: RemoteCommandController(playback: playback),
                nowPlaying: NowPlayingController()
            ))
        } catch {
            return .failed(Failure(message: String(describing: error)))
        }
    }
}

// MARK: - Playback

extension AppModel {
    /// The one `Playback`, or `nil` while `launchState` isn't `.ready`. Old singletons that can't
    /// read the environment reach it through `AppModel.current?.playback`.
    var playback: Playback? {
        guard case .ready(let ready) = launchState else { return nil }
        return ready.playback
    }
}

// MARK: - Database path and legacy input

extension AppModel {
    /// `Documents/jimmy.db`, the same file `DatabaseManager` opens today.
    static func defaultDatabasePath() -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsDirectory.appendingPathComponent("jimmy.db").path
    }

    /// A fresh, private path for unit tests, never the user's real database.
    static func temporaryDatabasePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModel-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// Chooses the on-disk database path for this launch: `DemoLibrary`'s throwaway temp path
    /// when `-demoLibrary` is passed (see `DemoLibrary.seed(into:)`, called separately once the
    /// store opens), a temp path for unit tests, and the user's real `Documents/jimmy.db`
    /// otherwise — in that priority order, so a demo-library test launch never touches the real
    /// database even if `XCTestConfigurationFilePath` also happens to be set.
    static func launchDatabasePath(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isRunningUnitTests: Bool
    ) -> String {
        if DemoLibrary.isRequested(arguments: arguments) {
            return DemoLibrary.makeDatabasePath()
        }
        if isRunningUnitTests {
            return temporaryDatabasePath()
        }
        return defaultDatabasePath()
    }

    /// Reads today's legacy sources from disk, for `Store`'s one-time `v20_legacy_import`
    /// migration. Keys and paths match what the old app writes today:
    /// `AudioPlayerService.lastPlayingEpisodeID`, `GRDBRepositories`/`PodcastRepository`'s
    /// `"saved_podcasts"`, the old queue's `"episode_queue"`, `FileStorage`'s
    /// `Documents/AppData/podcasts.json`, and `ListeningStatsService`'s
    /// `Documents/listening_stats.json`.
    static func legacyInputFromDisk() -> LegacyInput {
        let defaults = UserDefaults.standard
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        var lastPlayedEpisodeID: UUID?
        if let episodeIDString = defaults.string(forKey: "lastPlayingEpisodeID") {
            lastPlayedEpisodeID = UUID(uuidString: episodeIDString)
        }

        return LegacyInput(
            savedPodcastsData: defaults.data(forKey: "saved_podcasts"),
            appDataPodcastsData: documentsDirectory
                .flatMap { try? Data(contentsOf: $0.appendingPathComponent("AppData/podcasts.json")) },
            episodeQueueData: defaults.data(forKey: "episode_queue"),
            listeningStatsData: documentsDirectory
                .flatMap { try? Data(contentsOf: $0.appendingPathComponent("listening_stats.json")) },
            lastPlayedEpisodeID: lastPlayedEpisodeID
        )
    }
}

// MARK: - Queue

extension AppModel {
    /// The one `Store`, or `nil` while `launchState` isn't `.ready`. Shared by every
    /// `AppModel+*.swift` extension in this module (queue, library, ...).
    var readyStore: Store? {
        guard case .ready(let ready) = launchState else { return nil }
        return ready.store
    }

    /// The queue's episode ids, in play order.
    var queueEpisodeIDs: [UUID] { queue.map(\.id) }

    /// Whether `episodeID` is currently queued.
    func isQueued(_ episodeID: UUID) -> Bool {
        queue.contains { $0.id == episodeID }
    }

    /// Inserts (or moves, if already queued) `episodeID` to `position` (1 = first). Omitting
    /// `position` appends to the end of the queue.
    ///
    /// Posts the same `.episodeAddedToQueue`/`.queueOrderChanged` notifications the old
    /// `GRDBPlaybackStateRepository` used to, so old `ObservableObject` view models that can't
    /// use `@Observable` tracking (unlike a SwiftUI view body reading `AppModel` directly) stay
    /// live without each one re-implementing its own polling.
    func enqueue(_ episodeID: UUID, at position: Int? = nil) async {
        guard let readyStore else { return }
        // Read the live queue rather than trusting `self.queue`: it's only refreshed
        // asynchronously by `observeQueue()`, so it can still be stale immediately after a
        // preceding enqueue/dequeue call on the same episode-adding sequence.
        let currentQueue = (try? await readyStore.queue()) ?? []
        let wasQueued = currentQueue.contains { $0.id == episodeID }
        try? await readyStore.enqueue(episodeID, at: position ?? currentQueue.count + 1)
        NotificationCenter.default.post(name: wasQueued ? .queueOrderChanged : .episodeAddedToQueue, object: episodeID)
    }

    /// "Play Next": inserts (or moves) `episodeID` to position 2, right after whatever's playing.
    func playNext(_ episodeID: UUID) async {
        await enqueue(episodeID, at: 2)
    }

    /// Moves an already-queued `episodeID` to the front of the queue. A no-op if it isn't queued.
    func moveToTop(_ episodeID: UUID) async {
        await moveInQueue(episodeID, to: 1)
    }

    /// Moves an already-queued `episodeID` to the end of the queue. A no-op if it isn't queued.
    func moveToBottom(_ episodeID: UUID) async {
        guard let readyStore else { return }
        let currentQueue = (try? await readyStore.queue()) ?? []
        await moveInQueue(episodeID, to: currentQueue.count)
    }

    /// Moves an already-queued `episodeID` to `position` (1 = first).
    func moveInQueue(_ episodeID: UUID, to position: Int) async {
        guard let readyStore else { return }
        try? await readyStore.moveInQueue(episodeID, to: position)
        NotificationCenter.default.post(name: .queueOrderChanged, object: episodeID)
    }

    /// Removes `episodeID` from the queue, if present.
    func dequeue(_ episodeID: UUID) async {
        guard let readyStore else { return }
        try? await readyStore.dequeue(episodeID)
        NotificationCenter.default.post(name: .episodeRemovedFromQueue, object: episodeID)
    }

    /// Removes every queued episode belonging to `podcastID` (e.g. on unsubscribe).
    func removeEpisodesFromPodcast(_ podcastID: UUID) async {
        guard let readyStore else { return }
        let currentQueue = (try? await readyStore.queue()) ?? []
        for episode in currentQueue where episode.podcastID == podcastID {
            try? await readyStore.dequeue(episode.id)
        }
    }

    /// Empties the queue.
    func clearQueue() async {
        guard let readyStore else { return }
        let currentQueue = (try? await readyStore.queue()) ?? []
        for episode in currentQueue {
            try? await readyStore.dequeue(episode.id)
        }
    }

    /// Moves every queued episode to a random position.
    func shuffleQueue() async {
        guard let readyStore else { return }
        var ids = ((try? await readyStore.queue()) ?? []).map(\.id)
        ids.shuffle()
        for (index, episodeID) in ids.enumerated() {
            try? await readyStore.moveInQueue(episodeID, to: index + 1)
        }
    }

    /// Replaces the whole queue with `episodeIDs`, in order (e.g. importing a backup or merging
    /// an iCloud sync payload). Unknown or already-deleted episode ids are silently skipped.
    func replaceQueue(withEpisodeIDs episodeIDs: [UUID]) async {
        guard let readyStore else { return }
        let currentQueue = (try? await readyStore.queue()) ?? []
        for episode in currentQueue {
            try? await readyStore.dequeue(episode.id)
        }
        for (index, episodeID) in episodeIDs.enumerated() {
            try? await readyStore.enqueue(episodeID, at: index + 1)
        }
    }

    /// Resolves the queue's episode ids into the old app's richer `Episode` model (progress,
    /// played state, title, artwork — fields `JimmyKit.Episode` doesn't carry yet), for the old
    /// singletons that still render or export them. Goes away once those callers move onto
    /// `JimmyKit` directly in later PRs.
    func resolveQueueEpisodes() async -> [Jimmy.Episode] {
        var episodes: [Jimmy.Episode] = []
        for episodeID in queueEpisodeIDs {
            if let episodeWithState = try? await DIContainer.shared.episodeRepository.fetchEpisode(by: episodeID) {
                episodes.append(episodeWithState.episode)
            }
        }
        return episodes
    }
}

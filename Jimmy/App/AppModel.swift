import Foundation
import Observation
import JimmyKit

/// Owns the one JimmyKit `Store` every screen will eventually read and write through, and the
/// `Playback` object built on top of it. Opened synchronously, before any old service
/// (`DatabaseManager`, `DIContainer`, ...) touches the same file — see `JimmyApp.init()`.
///
/// Screens still run on the old services until they move onto `JimmyKit` one at a time in later
/// PRs, so nothing reads from `store` or drives `playback` yet; `AudioPlayerService` keeps owning
/// audio, remote commands and Now Playing until PR 16.
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
    }

    struct Failure {
        /// Description of the error `Store.init` threw, shown as-is on the launch failure screen.
        let message: String
    }

    private(set) var launchState: LaunchState

    private let databasePath: String
    private let legacyInput: () -> LegacyInput?

    init(databasePath: String, legacyInput: @escaping () -> LegacyInput? = { nil }) {
        self.databasePath = databasePath
        self.legacyInput = legacyInput
        self.launchState = Self.open(databasePath: databasePath, legacyInput: legacyInput())
    }

    /// Tries opening the store again at the same path, e.g. after the user tapped "Try Again".
    func retry() {
        launchState = Self.open(databasePath: databasePath, legacyInput: legacyInput())
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
                progressStore: StorePlaybackSource(store: store),
                queueSource: StorePlaybackSource(store: store)
            )
            return .ready(Ready(store: store, playback: playback))
        } catch {
            return .failed(Failure(message: String(describing: error)))
        }
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

    /// Reads today's legacy sources from disk, for `Store`'s one-time `v20_legacy_import`
    /// migration. Keys and paths match what the old app writes today:
    /// `AudioPlayerService.lastPlayingEpisodeID`, `GRDBRepositories`/`PodcastRepository`'s
    /// `"saved_podcasts"`, `QueueViewModel`'s `"episode_queue"`, `FileStorage`'s
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

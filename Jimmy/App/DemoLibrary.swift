import Foundation
import JimmyKit

/// Seeds a throwaway library for `-demoLibrary` screenshots: a handful of public feeds with real
/// artwork and English titles, a few queued episodes, and one episode loaded into `Playback`
/// paused partway through — so Queue, Library and Now Playing all have real content to show.
/// `seed(into:)` runs on every `-demoLibrary` launch (not just the first), since `Playback` is
/// in-memory per process even when the underlying database is reused across relaunches.
///
/// Only ever runs against `AppModel.launchDatabasePath(...)`'s demo path (a fresh temp file),
/// never the user's real `jimmy.db` — see `JimmyApp.init()`, which is the only caller.
enum DemoLibrary {
    /// The launch argument that switches `JimmyApp` onto this throwaway demo library.
    static let launchArgument = "-demoLibrary"

    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    /// A fresh, private path for the demo library, in a temp directory — never the user's real
    /// database.
    ///
    /// `JIMMY_DEMO_DB_ID` — set by `Tools/screenshots.sh` as a `SIMCTL_CHILD_` environment
    /// variable, since `xcrun simctl launch` only otherwise accepts extra argv, not env vars —
    /// keeps every relaunch in one screenshot run on the same demo database, so `seed(into:)`
    /// only has to subscribe to the demo feeds over the network once per run (see its own early
    /// return below), not once per screen captured. Any other `-demoLibrary` launch (a plain
    /// `make run`, say) falls back to a fresh id, same as before.
    static func makeDatabasePath() -> String {
        let runID = ProcessInfo.processInfo.environment["JIMMY_DEMO_DB_ID"] ?? UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModel-Demo-\(runID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("jimmy.db").path
    }

    /// If `Tools/screenshots.sh` asked for a specific screen via `JIMMY_SCREENSHOT_ROUTE` (a
    /// `jimmy://` URL, passed the same `SIMCTL_CHILD_` way as `JIMMY_DEMO_DB_ID`), navigates there
    /// in-process through the same `DeepLinkRouter` a real `jimmy://` deep link uses. Deliberately
    /// never goes through `UIApplication.open(_:)` (what `xcrun simctl openurl` drives) — that path
    /// can trigger iOS's "Open in…" confirmation, which blocks the simulator until a human taps it
    /// away, something a screenshot script run from the command line has no way to do.
    @MainActor
    static func navigateToScreenshotRouteIfRequested() {
        guard let routeString = ProcessInfo.processInfo.environment["JIMMY_SCREENSHOT_ROUTE"],
              let routeURL = URL(string: routeString),
              let deepLink = DeepLinkRouter.shared.parse(url: routeURL) else { return }
        DeepLinkRouter.shared.navigate(to: deepLink)
    }

    /// Public feeds picked for reliable artwork and English titles — verified to parse with
    /// `FeedParser` (title, artwork and audio enclosures all present) before being added here.
    static let feedURLs: [URL] = [
        "https://feeds.npr.org/510289/podcast.xml", // Planet Money
        "https://www.thisamericanlife.org/podcast/rss.xml", // This American Life
        "https://feeds.simplecast.com/EmVW7VGp", // Radiolab
        "https://feeds.simplecast.com/BqbsxVfO", // 99% Invisible
        "https://feeds.simplecast.com/6HKOhNgS", // Hard Fork
        "https://rss.amperwave.net/v2/feed/audacynetwork/search-engine", // Search Engine
    ].compactMap(URL.init(string:))

    /// How many episodes (across distinct podcasts, for visual variety) to add to the queue.
    private static let queuedEpisodeCount = 4

    /// Where to pause the Now Playing episode, so the mini player and Now Playing screen show a
    /// mid-episode position instead of 0:00.
    private static let nowPlayingPosition: TimeInterval = 12 * 60

    /// Subscribes to `feedURLs`, queues a handful of recent episodes, and loads the first of them
    /// into `Playback`, paused at `nowPlayingPosition`. Called from `JimmyApp.init()`, guarded by
    /// `isRequested()`, on every launch — not just the first. Every store call is best-effort
    /// (`try?`): a feed that fails to fetch (no network in CI, a feed moved) just leaves the
    /// library with fewer shows rather than failing the launch.
    @MainActor
    static func seed(into model: AppModel) async {
        guard let store = model.readyStore else { return }

        // A later launch against the same demo database within one screenshot run (see
        // `makeDatabasePath()`) already has the feeds subscribed and episodes queued — this skips
        // re-fetching them over the network again. `Playback` itself, below, is in-memory per
        // process though, so it still has to be set up fresh on every launch (`Tools/
        // screenshots.sh` relaunches once per screen): without that, only the very first launch
        // would ever show Now Playing with content, and every later screenshot of it would show
        // "Nothing Is Playing" despite the queue being fully seeded.
        let alreadySeededCount = (try? await store.podcasts().count) ?? 0
        let needsSeeding = alreadySeededCount < feedURLs.count

        if needsSeeding {
            for feedURL in feedURLs {
                _ = try? await model.subscribe(feedURL: feedURL)
            }
        }

        let podcasts = (try? await store.podcasts()) ?? []
        guard !podcasts.isEmpty else { return }

        // Queue (and anything else still reading through `DIContainer.shared.episodeRepository`)
        // resolves queue membership into richer per-row data from the legacy repository — see
        // `QueueView`'s doc comment — whose `episodes.podcastID` is a foreign key against the
        // legacy `podcasts` table. Without these rows, `model.ensureEpisodeIsSaved(_:)` below
        // would silently fail its own insert (every legacy write goes through `try?`), and every
        // demo episode would be invisible there despite being enqueued correctly.
        if needsSeeding {
            _ = try? await DIContainer.shared.podcastRepository.savePodcasts(podcasts.map { $0.asLegacyPodcast() })
        }

        var nowPlayingEpisode: JimmyKit.Episode?
        var queuedCount = 0

        for podcast in podcasts {
            guard queuedCount < queuedEpisodeCount else { break }
            let episodes = (try? await store.episodes(podcastID: podcast.id)) ?? []
            guard let episode = episodes.first(where: { $0.audioURL != nil }) else { continue }

            if needsSeeding {
                await model.ensureEpisodeIsSaved(episode)
                await model.enqueue(episode.id)
            }
            queuedCount += 1
            if nowPlayingEpisode == nil {
                nowPlayingEpisode = episode
            }
        }

        guard let nowPlayingEpisode else { return }
        await model.play(nowPlayingEpisode, startPlaying: false)
        await model.playback?.seek(to: nowPlayingPosition)
    }
}

# Architecture

Jimmy is a queue-centric podcast app built on Swift and SwiftUI. This document describes how the pieces fit
together.

Jimmy is one SwiftUI app over a core Swift package, **JimmyKit**. Most of the app now runs on JimmyKit; a few
older app-side services in `Jimmy/Services` are still being moved over, and each move deletes the code it replaces.

### Targets

| Target | Platform | Sources | Bundle ID |
|---|---|---|---|
| Jimmy | iOS 27+ (iPhone; iPad in compatibility mode) | `Jimmy/` | `com.chenkahana.Jimmy` |
| JimmyWatch | watchOS 27+ | `JimmyWatch/` | `com.chenkahana.Jimmy.watchkitapp` |
| JimmyKit | iOS 27+, watchOS 27+, macOS 26+ (Swift package) | `Packages/JimmyKit` | — |

The Xcode project is generated from `project.yml` via XcodeGen; edit the YAML file, never the generated project.

### Data model

Plain value types in `Packages/JimmyKit/Sources/JimmyKit/Model/`, one per file; the store layer adds GRDB
conformances on top of them:

- **Podcast**: a subscribed podcast with title, URL, artwork and metadata.
- **Episode**: an episode of a podcast with title, description, publish date and media URL.
- **QueueEntry**: an episode's position in the play queue.
- **Progress**: playback progress for an episode (position, duration, completion state) — the single
  source of truth for "finished", replacing the old scattered flags.
- **Download**: a downloaded episode file (relative path, size, state).
- **Playlist**: a smart playlist definition (name plus a rule).
- **Bookmark**: a user note at a timestamp in an episode.
- **Transcript** / **Chapter**: episode transcript and chapter-marker data.
- **ListeningStat**: a day's listening time, optionally attributed to a podcast.

`Store` is the single source of truth. It opens a GRDB `DatabasePool` (WAL mode), runs versioned migrations and
exposes async reads and writes such as `queue()` and `enqueue(…)`. `LegacyMigrations` carries a library over from
older versions of Jimmy on first launch.
A shipped migration is never edited; schema changes add a new one.

### Services and APIs

**JimmyKit** exports:

- **Store** (`Store`): async database access, the data model and migrations.
- **Feeds** (`FeedFetcher`, `FeedParser`, `FeedRefresher`): fetch, parse and refresh RSS/Atom feeds.
- **Playback** (`Playback`): one episode at a time, saved positions, auto-advance, sleep timer and chapters, over
  protocol seams (`PlayerEngine`, `ProgressStore`, `QueueSource`, `Clock`) so it is tested without audio.
- **Downloads** (`Downloads`, `DownloadReconciler`): background `URLSession` downloads that survive relaunch.
- **Import** (`OPMLParser`, `AppleBulkImportParser`, `SpotifyListParser`, `GoogleTakeoutParser`): bring a library
  in from other apps.
- **Discover** (`PodcastDirectory`) and **Suggestions** (`SuggestionsRanker`): search, top charts and Up Next.
- **WatchSession**: the value types the phone and watch exchange over WatchConnectivity.

The app has one `@Observable AppModel` (split into `AppModel+<Area>.swift` extensions) that holds the current
queue, now-playing episode, app state and app-level navigation. Views use SwiftUI bindings to the model and call methods to perform actions (play, pause, add to queue, etc.).

### UI structure

All UI is SwiftUI. The tabs are **Queue**, **Library** and **Search**, with a mini player above the tab bar that
opens **Now Playing**. Settings and Listening Stats open from Library's More menu, and the on-device Assistant
from Settings.

CarPlay (`Jimmy/CarPlay`) reads the same `AppModel`. The watch app gets its state from the phone over
WatchConnectivity (`AppModel+WatchSession.swift`) and sends commands back through the same methods the phone's UI
uses.

### Concurrency

The app uses Swift async/await throughout. All UI code is `@MainActor` by default. All database work, feed fetching
and playback session changes run off the main actor through JimmyKit's async API, so the UI never blocks on I/O.

### Persistence

Podcast and episode data, queue state and playback progress are stored in a local SQLite database managed by GRDB.
Nothing is uploaded to any server. Optional iCloud sync writes a small record (subscriptions, queue order,
progress) to the user's own iCloud key-value store.
Downloads are stored as files in the app's documents directory.

### Privacy and security

- No analytics, crash reporting or third-party SDKs that collect data.
- No accounts or sign-in. All data stays on the device.
- Feeds are fetched directly from podcast hosts; no proxy or aggregation service is used.
- See [privacy.md](privacy.md) for the user-facing policy.

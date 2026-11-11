# Architecture

Jimmy is a queue-centric podcast app built on Swift/SwiftUI. This document describes how the pieces fit together
and will be updated as the simplification (per PLAN.md) progresses.

## Current state (in progress)

Jimmy is being refactored from a monolithic app into a layered architecture. The target design below is under development.

## Target architecture

Jimmy is one SwiftUI app over a core Swift package, **JimmyKit**.

### Targets

| Target | Platform | Sources | Bundle ID |
|---|---|---|---|
| Jimmy | iOS 27+ (iPhone; iPad in compatibility mode) | `Jimmy/` | `com.chenkahana.Jimmy` |
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

`JimmyStore` is the single source of truth. It opens a `DatabasePool` (WAL mode) in the app's documents directory,
runs versioned migrations (`v1`, `v2`, …) and exposes reads such as `loadQueue()` and writes such as `addToQueue()`.
A shipped migration is never edited; schema changes add a new one.

### Services and APIs

**JimmyKit** exports:

- **Store** (`JimmyStore`): async database access, the data model and migrations.
- **Fetcher** (`FeedFetcher`): feeds podcasts and updates subscription metadata asynchronously.
- **Parser** (`RSSParser`): parses RSS/Atom feeds into `Episode` models.
- **Playback** (`PlaybackSession`): playback state, progress tracking and queue management.
- **Downloads** (`DownloadManager`): episode file downloads with resume and cleanup.

The app has one `@Observable AppModel` that holds the current queue, now-playing episode, app state and app-level
navigation. Views use SwiftUI bindings to the model and call methods to perform actions (play, pause, add to queue, etc.).

### UI structure

All UI is SwiftUI. The app targets:

- **Queue screen**: primary UI, shows the current queue and now-playing controls.
- **Library screen**: subscriptions, browse, and search.
- **Settings screen**: preferences, app info and about.
- **Now playing screen**: full-screen playback with controls and metadata.

CarPlay and Apple Watch are planned to read the same `AppModel` and `JimmyStore`.

### Concurrency

The app uses Swift async/await throughout. All UI code is `@MainActor` by default. All database work, feed fetching
and playback session changes run off the main actor through JimmyKit's async API, so the UI never blocks on I/O.

### Persistence

Podcast and episode data, queue state and playback progress are stored in a local SQLite database managed by GRDB.
Nothing is uploaded to any server. iCloud key-value store (if implemented) stores small preferences only.
Downloads are stored as files in the app's documents directory.

### Privacy and security

- No analytics, crash reporting or third-party SDKs that collect data.
- No accounts or sign-in. All data stays on the device.
- Feeds are fetched directly from podcast hosts; no proxy or aggregation service is used.
- See [privacy.md](privacy.md) for the user-facing policy.

# Jimmy: the Boaz treatment

Goal: make Jimmy as simple, stable and correct as Boaz without losing the user's library or the features that matter.

## Where Jimmy is (2026-11-11, `main` at 28a205a)

| | Jimmy | Boaz |
|---|---|---|
| Swift | 71k lines, one iPhone app | 19k lines, iPhone + Mac + extensions |
| Structure | 99 service files (27k lines), 6 types for the podcast collection, 3+ RSS parsers, 2 GRDB layers, 4 caches, 6 performance monitors | One core package (models, GRDB store, sync) and thin apps |
| State | 77 `ObservableObject`, 115 singletons, a DI container, 88 NotificationCenter uses | One `@Observable` model per scene |
| Swift mode | Swift 5, no concurrency checking, 30+ `Task.detached` | Swift 6, main-actor by default |
| Crashes | `fatalError` at launch if the database can't open (`DatabaseManager.swift:51,1039`) | Errors are shown, the app keeps running |
| Tests | 18 unit test files, 9 about the tab bar; none for playback, feeds, the database or downloads | No tests yet in BoazKit (Jimmy adds them in phase 1) |
| CI | 4 workflows; `ci.yml` is invalid YAML and never runs; Performance Monitoring has failed every day for 10+ days | 1 build workflow, kept green (Jimmy's will also be SHA-pinned) |
| Repo | 17 open PRs (oldest 2025-06; #132 the latest "stability overhaul", draft); tracked `.kiro/`, `version 3/`, result folders; 8 stale progress docs; no README or CHANGELOG | Clean root, current docs, CHANGELOG, QA and release guides |
| Project | Hand-edited `.xcodeproj`, a side `Package.swift` over some of the app's files | XcodeGen `project.yml`, `make` targets |

Earlier stability attempts (#89, #91, #93, #113, #132) each added layers next to the old code instead of replacing it. That's how Jimmy got to 71k lines. This plan replaces and deletes.

## Approach: new core, then move screens onto it

Not a rewrite in one go, and not more layers. Build a small tested core next to the app, move one screen at a time onto it, and delete the old code that screen used, in the same PR. The app keeps working after every step, and the user's library carries over.

## Phases

### 0. Clean the ground (days)
- Close the stale PRs (done; list at the end).
- Remove tracked clutter (`.kiro/`, `.agent/`, `version 3/`, `MJGA/`, `*_results/`, stale `docs/PHASE_*` and progress logs).
- Remove Firebase (Analytics, Crashlytics, `GoogleService-Info.plist`) and its wrappers.
- One `ci.yml` like Boaz (SHA-pinned, checksum-verified tools, build + tests); delete the other three workflows.
- XcodeGen `project.yml` and a `Makefile` (`make build`, `make test`, `make archive`); drop the side `Package.swift`.
- README, CHANGELOG, `docs/architecture.md`.

### 1. Safety net before touching behavior
- Copy a real library database (anonymized) as a test fixture; a test proves the new store opens it with nothing lost.
- 20–30 real feeds saved as fixtures (Apple, Libsyn, Megaphone, malformed XML, missing enclosures, odd dates).
- Tests for queue order, played/progress rules and import parsers (OPML, Apple, Spotify, Google Takeout).

### 2. JimmyKit (Swift 6, main-actor default)
- Models: Podcast, Episode, QueueEntry, Progress, Download, Playlist.
- One GRDB store with migrations from today's schema; one writer; no UserDefaults for data.
- One feed fetcher and one RSS parser; refresh with a concurrency limit, timeouts and per-feed errors.
- Downloads with background `URLSession` and paths stored relative to the container.
- Unit tests with the fixtures from phase 1.

### 3. One player
- `Playback` (`@Observable`): owns `AVPlayer`, the audio session (interruptions, route changes), Now Playing, remote commands, sleep timer, and saves position at most every few seconds.
- CarPlay and the mini player read the same object.

### 4. Move the app onto the core, screen by screen
- One `@Observable` app model in place of the singletons, DI container and NotificationCenter.
- Order: Queue → Player/Mini player → Library → Podcast detail/Episode → Discover/Search → Settings/Import → CarPlay.
- Each PR deletes the old services that screen used. Target: about 15k lines.
- Apple Watch app (watchOS 27, JimmyKit models): Now Playing, Queue, Recent; controls the phone's player.
  Standalone playback on the watch comes later.

### 5. On-device AI
- Apple's on-device model only (Foundation Models), as Boaz does: nothing leaves the phone.
- **Chat that acts:** "play the latest Daily", "queue the newest episodes of my news shows", "find episodes about sleep",
  "set a 20-minute sleep timer". The model calls tools that are thin wrappers over the app model (play, queue, search,
  subscribe, timer) and says what it did; anything destructive (unsubscribe, clear queue) asks first.
- **Suggestions:** "Up next" picks from your library and listening history, and new shows like the ones you finish.
  Ranked on device; the model writes the one-line reason.
- Clear message when Apple Intelligence isn't available; the rest of the app is unaffected.

### 6. Open-source ready (like Boaz)

Early, in phase 0 (no app changes):
- `LICENSE` (MPL-2.0, as Boaz), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`,
  `THIRD_PARTY_NOTICES.md` (GRDB and anything else bundled), `CHANGELOG.md`.
- `.github/`: issue templates (bug, feature), PR template, `CODEOWNERS`, Dependabot for Actions only.
- `docs/architecture.md` and `docs/privacy.md` (what stays on the phone; no analytics once Firebase is gone).

At the end, once the screens have moved and the design is settled:
- **Screenshots:** a fixed demo library (public feeds, seeded by a launch argument) so every shot is reproducible;
  captured from the simulator in light and dark: Queue, Now Playing, Library, Podcast, Discover, AI chat, CarPlay.
  A hero image and an app-icon header, as in Boaz's README.
- **README:** icon, one-line pitch, badges (CI, iOS version, Swift, license), feature table, screenshots, architecture
  summary, getting started (`make bootstrap`, `make build`), privacy, contributing, license.
- **Security pass before going public** (as Boaz had): secret scan of the whole history, CI hardening
  (SHA-pinned actions, least-privilege tokens), no keys in the repo.
- **Going public:** flip the repo to public, then turn on what that unlocks for free: rulesets on `main`
  (PR + CI required, owner and ChenK14 bypass for PRs), secret scanning and push protection, private vulnerability
  reporting.

Found already, to settle before going public:
- `GoogleService-Info.plist` is in 4 commits of history (a Firebase API key; low-risk by design, but public).
- 161 of 406 commits are authored with the work address `chenk@wix.com`.
- Old planning folders and progress logs throughout history.

### 7. Prove it, the Boaz way
- `docs/qa.md` with the full checklist; hands-on QA rounds (Codex) like Boaz's, with speed and memory numbers.
- Launch never crashes on a bad database: it shows an error and offers a reset.
- Release guide (TestFlight / App Store), CHANGELOG, version tags.

## Done means
- Every phase merged with green CI; no `fatalError` outside `init(coder:)`.
- The library from today's app opens unchanged (fixture test + one real device).
- Swift 6 mode everywhere, no `@unchecked Sendable`, no `Task.detached` without a reason in a comment.
- Hands-on QA finds no P1 or P2.
- The repo is public, with a README, screenshots and community files that match Boaz.

## Decisions (Chen, 2026-11-11)
1. Approach: new core, then move screens onto it.
2. Firebase: removed. Crashes come from Xcode Organizer and MetricKit.
3. Features kept: smart playlists, transcripts, chapters, bookmarks, listening stats, Apple Watch, recommendations,
   feedback form, shake to undo. New: AI chat that acts on requests, and AI suggestions (phase 5).
4. Open PRs: all closed, with the list below kept for anything worth redoing.
5. Open source: Jimmy goes public once phase 6 is done, starting from one clean commit (author
   `chenkahana` noreply address, no Firebase file, no old planning folders). The current private history stays in a
   private archive repo (`Jimmy-archive`) for reference.
6. Minimum iOS 27 for the app and JimmyKit (as Boaz); watchOS 27 for the watch app.
7. Apple Watch: today there is only `WatchConnectivityService` and no watch target; a real watch app is built in phase 4.
8. Execution: parallel lanes of subagents, Haiku for mechanical work, Sonnet for code, an Opus review per code PR.
   The PR list and lanes are in `tasks/todo.md`.

## Closed PRs worth a second look later
- #117 news RSS headlines widget (feature idea).
- #116 subscription import reliability, OPML error handling (fold into phase 1 import tests).
- #86 local audio import episodes not showing (check the bug still exists after phase 4).
- #29 Discover page style (design reference).

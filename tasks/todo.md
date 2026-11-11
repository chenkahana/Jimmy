# Jimmy simplification: PR checklist

Direction and decisions are in `PLAN.md`. Each line is one PR. H = Haiku (mechanical), S = Sonnet (code); every S PR gets an Opus review before merge.
Lanes in the same wave run in parallel, each in its own worktree under `~/.worktrees/Jimmy/<branch>`, and never touch the same files.

## Wave A: phase 0 and fixtures
- [x] 1. `PLAN.md` decisions (iOS 27, Watch app, execution) and this checklist (main session)
- [x] 2. Remove tracked clutter (H)
- [x] 3. Remove Firebase; `os.Logger` + MetricKit (S)
- [x] 6. Community files, `docs/architecture.md`, `docs/privacy.md` (H)
- [x] 7. Feed XML and UserDefaults/JSON fixtures (H)
- [ ] 7b. A real `jimmy.db` from Chen's phone, anonymized; run `Store` against it before PR 14
- [x] 5. XcodeGen `project.yml` + `Makefile`, iOS 27; drop side `Package.swift` (S, after 3)
- [x] 4. One SHA-pinned `ci.yml`, Dependabot for Actions; delete old workflows and their scripts (H, after 5)
- [x] 8. Characterization tests: queue order, played/progress, OPML/Apple/Spotify/Takeout (S, after 5)

## Wave B: JimmyKit and the player
- [x] 9a. `Packages/JimmyKit` scaffold (Swift 6, MainActor default, GRDB 7) and models (S)
- [x] 9b. Store: frozen legacy migrations v1–v17 in today's order, v18–v21, no `fatalError`/`:memory:` (S)
- [x] 10. One feed parser and fetcher, bounded refresh (S)
- [x] 12. Import parsers moved into JimmyKit (S)
- [x] 13. `Playback` (S)
- [x] 11. Downloads, background session, relative paths (S, after 9b)

## Wave C: screens onto the core (each deletes what it replaces)
- [x] 14. `AppModel`, startup error screen with reset (S)
- [x] 15. Queue (S). `v19_progress` copied progress and queue once when PR 14 first opened the store; the old app kept writing `episodes`/`playback_state` since. Before reading `progress`/`queue` from the store, add a migration that re-runs the backfill from the legacy tables.
- [x] 16. Player and mini player (S). Before deleting `AudioPlayerService`, bring over what `Playback` (PR 13) left out: trim silence and volume boost (`AudioEnhancementService`), sleep-timer fade-out, listening-stats tracking, Now Playing artwork loading, widget data. `v19_progress` copied progress once when PR 14 first opened the store; the old app kept writing `playback_state` since (PR 15 already made the queue self-resyncing via `v23_resync_queue`). Before reading `progress` from the store, add a migration that re-runs the progress backfill from the legacy tables.
  - Note: whichever PR deletes the old `DownloadManager` (not yet assigned a number above — candidates are 16 or 17/18, since downloads surface in both the player and the episode/library rows) is where `Downloads` joins `AppModel`: JimmyKit's `Downloads` uses the same background `URLSession` identifier (`com.chenkahana.Jimmy.downloads`) as `DownloadManager`, and a process can't run two sessions on one identifier.
- [x] 17. Library (S)
- [ ] 18. Podcast detail and Episode (S). PR 16 added `Jimmy/App/LegacyProgressMirror.swift` — a `ProgressStore` wrapper that saves through `StorePlaybackSource` and also mirrors into the legacy `episodes.playbackPosition`/`played`/`status` and `playback_state.position`/`finished` columns, since Library/podcast detail/episode rows still read those until they move onto JimmyKit here. Delete `LegacyProgressMirror` and build `Playback` with a bare `StorePlaybackSource` once this PR moves those screens onto `progress` directly.
- [ ] 19. Discover and Search (S)
- [ ] 20. Settings and Import (S)
- [x] 21. CarPlay (S)
- [ ] 23. Apple Watch app (S, parallel lane after 16)
- [x] 24. AI chat that acts (S, parallel lane after 14)
- [ ] 25. AI suggestions (S, after 24)

## Wave D: finish and go public
- [ ] 22. Sweep: caches, monitors, DI, `Domain/`, `Data/`; app to Swift 6 (S, after 21)
- [ ] 26. Demo library + screenshots + README (H script, S seeding)
- [ ] 27. `docs/qa.md` and QA rounds (H)
- [ ] 28. Release guide, v8.0 tag (H)
- [ ] 29. Going public, each step approved by Chen (main session)

## Only Chen
- Export `jimmy.db` from the phone (PR 7).
- Real-device check of the real library (PR 9b).
- Go-ahead for each step of PR 29.

## Review

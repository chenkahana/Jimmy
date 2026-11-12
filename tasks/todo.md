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
- [x] 18. Podcast detail and Episode (S). `PodcastDetailView`/`PodcastEpisodeListView`/`EpisodeDetailView` now read episodes, progress, queue, download state, bookmarks, transcripts, and chapters through `AppModel` → `Store` (new `Store+Episodes.swift`, `EpisodeListItem`, `AppModel+Episodes.swift`). `EpisodeService` and the old streaming episode stack are deleted.
  - `LegacyProgressMirror` was **kept** (not deleted) — `QueueView`, `SmartPlaylistService`, `AppDataDocument`, `SharedDataStore`, `EpisodeIDMigrationService`, `CarPlayManager`, and `ProgressCacheStore`/`SubscriptionViewModel` (via `.episodeStatusUpdated`) still read the legacy `episodes.playbackPosition`/`played`/`status` and `playback_state` columns; those are out of this PR's scope (CarPlay is PR 21). A new shared `LegacyEpisodeStatusMirror` helper (used by both `AppModel.markPlayed/markUnplayed` and `LegacyProgressMirror`) keeps those readers in sync now that `EpisodeService` is gone.
  - `DIContainer` was **kept, not deleted** — shrunk by one dead member (`downloadManager`). Ten `lazy var` members remain, each with real external callers outside this PR's scope: `episodeRepository`/`podcastRepository`/`playbackStateRepository` (QueueView, SubscriptionViewModel, AppDataDocument, SmartPlaylistService, CarPlayManager, PodcastSearchView/PodcastGridComponent/Discover, `ConcreteRSSParser`-backed fetches), plus others used by Settings/Search/CarPlay screens not yet moved onto `AppModel`.
  - `EpisodeUpdateService`, `EpisodeMergeHeap`, `EpisodeCacheService`, `GRDBRepositories.swift`, `ConcreteRSSParser.swift`, and `DownloadManager` were kept — each confirmed via `rg` to have real callers outside PR 18 scope (`DownloadManager` is explicitly deferred to a later PR per `AppModel.swift`'s doc comment).
- [x] 19. Discover and Search (S)
- [x] 20. Settings and Import (S). One `LocalAudioImporter` replaces `BulletproofAudioImporter`/
  `SharedAudioImporter`/`FileImportCoordinator` — local audio always lands on a fixed "Imported
  audio" show, an ordinary store-backed podcast, which also fixes #86 (its episodes now show up in
  `PodcastEpisodeListView` like any other podcast's). One `SubscriptionImporter` replaces
  `SubscriptionImportService`/`PodcastURLResolver`, parsing with JimmyKit's `Import/` parsers and
  subscribing through `AppModel.subscribe(feedURL:)`; an Apple/Spotify share link (not a feed)
  still resolves by title through `iTunesSearchService` — a title-only export row isn't supported
  yet (noted in `SubscriptionImporter`'s doc comment). Smart playlists and listening stats move
  onto new `Store` surfaces (`Store+Playlists.swift`, `Store+ListeningStats.swift`); listening-time
  tracking no longer polls a `Timer`. `AppDataDocument`/`BackupService` move off
  `DIContainer`/`DatabaseManager` onto `Store` (`Store+Backup.swift`). OPML export uses JimmyKit's
  `OPMLWriter`. `LegacyProgressMirror`/`LegacyEpisodeStatusMirror`/`DIContainer` are still kept —
  other readers remain outside this PR's scope (see PR 18's note above; this PR only removed
  `AppDataDocument` and smart playlists from that list).
- [x] 21. CarPlay (S)
- [ ] 23. Apple Watch app (S, parallel lane after 16)
- [x] 24. AI chat that acts (S, parallel lane after 14)
- [x] 25. AI suggestions (S, after 24)

## Wave D: finish and go public
- [ ] 22. Sweep: caches, monitors, DI, `Domain/`, `Data/`; app to Swift 6 (S, after 21)
  - Lane A (DI/legacy data layer) done. Moved `QueueView`, `SharedDataStore` (via
    `AppModel.resolveQueueEpisodes()`), `AppModel.markPlayed/markUnplayed`, and the Discover
    preview flow (`AsyncPodcastDetailView`/`PreviewEpisodeListView`, now via a new
    `AppModel.previewPodcast(feedURL:)`) off `DIContainer`/legacy columns onto `AppModel`/`Store`
    directly. Deleted: `LegacyProgressMirror`/`LegacyEpisodeStatusMirror` (built `Playback` with a
    bare `StorePlaybackSource`; `.episodeStatusUpdated` had no listeners left once `QueueView`,
    `ProgressCacheStore`, and `SubscriptionViewModel` moved/went), `DIContainer`,
    `Domain/Repositories/`, `Domain/UseCases/` (kept `Domain/Stores/MemoryCacheStore.swift` —
    lane B's), `Data/` (`GRDBRepositories.swift`), `Infrastructure/ConcreteRSSParser.swift`,
    `EpisodeUpdateService`, `EpisodeMergeHeap`, `EpisodeCacheService`, `EpisodeIDMigrationService`
    (dead — never called), `ProgressCacheStore`, `SubscriptionViewModel` (dead beyond a toast
    message LibraryView now holds itself), `PodcastCardViewModel`/`ImportAudioFileUseCase`/
    `LoadingOptimizer`/`FastLibraryLoader`/`Services/Core/ServiceMonitor.swift` (all dead, zero
    callers), `DatabaseManager` (nothing left needed it), `DownloadManager`/`DownloadsView`
    (`DownloadsView` was already unreachable from navigation; `Downloads` now joins `AppModel` —
    see `AppModel+Downloads.swift` — backing `resolveAudioURL` and `PodcastEpisodeListView`'s
    "Downloaded" filter; download *initiation* has no UI entry point yet, same as before). Added
    `Jimmy/Models/ShowMetadata.swift` (just the struct, un-migrated) since `MemoryCacheStore`
    (out of scope) still references it.
  - Kept, out of scope for lane A: `Domain/Stores/MemoryCacheStore.swift`/`MemoryCache`,
    performance monitors (`CircuitBreaker`, `PerformanceMonitor`, etc.) — lane B's. No Swift 6
    mode switch (separate step).
  - `make build`, `make test SIM="Jimmy Lane 4"` (202 passed), `make kit` (234 passed) all green.
  - Lane B (`sweep-infra`) deleted the performance-monitor/optimizer/engine cluster: `PerformanceMonitor`,
    `RealTimePerformanceMonitor`, `UIPerformanceManager`, `UIOptimizationService`, `InstantResponseEngine`,
    `PredictiveUserBehaviorEngine`, `PerformanceSafeguards`, `ScrollPerformanceOptimizer`, `LoadingOptimizer`,
    `MemoryMonitor`, `MemoryTracker`, `CacheCleanupService`, `SingletonLifecycleManager`, `WeakReferenceHelper`,
    `SimplePerformanceMonitor`, `MemoryOptimizationHelper`, `ServiceMonitor`, `LoadingStateCoordinator`,
    `UserFeedbackService`, `ResourceMonitor`, `OptimizedListComponents`, `OptimizedImageLoading`,
    `SmoothAnimations`, `LoadingStates` (view), `UIUpdateService`/`ServiceContainer` — all had zero real
    callers (only each other, or dead debug/settings UI nothing linked to). `CrashPreventionManager`,
    `ComponentRollbackService`, and `FeatureFlagService` (no flag ever actually gated behavior) went the
    same way; `FeatureFlagServiceTests` went with it.
  - `CircuitBreaker.swift` kept only the live `HostCircuitBreaker` actor (used by `UnifiedNetworkService`)
    and the `CircuitState`/`CircuitBreakerError` it needs; the unused `CircuitBreaker` class/statistics were
    cut.
  - `ProMotionManager` was trimmed to just what backs the live `Animation.proMotionEaseInOut`/`.proMotionSpring`
    helpers (used by `CachedAsyncImage`/`DiscoverView`) — the CADisplayLink monitoring, debug view, and
    environment-key plumbing were unused and dropped.
  - Image caches: kept `BulletproofImageCache` (the one actually wired through `BulletproofAsyncImage`,
    used in 15+ views) and deleted `ImageCache`; moved its three callers (`CachedAsyncImage`'s
    `PodcastArtworkView` family, `ImagePreloader`, `SettingsViewModel.clearAllCache`) onto
    `BulletproofImageCache` (added a small `clearAllCaches()` to match). `LibraryView`'s preload calls were
    already on `BulletproofImageCache`.
  - Removed the dead `.performanceAdaptive(baseSkeletonCount:)` modifier calls in `LibraryView`/`DiscoverView`/
    `PodcastSearchView` — it only set environment values nothing ever read.
  - Kept `MemoryCacheStore`/`MemoryCache` (`Jimmy/Domain/Stores/`, `Jimmy/Utilities/MemoryCache.swift`) and
    `IntelligentCacheEngine` (not found in the current tree) untouched: `MemoryCacheStore` is deeply wired
    into `GRDBRepositories.swift`/`DIContainer` (lane A's `Domain`/`Data`/DI territory) and isn't a one-line
    removal. DI/`Domain`/`Data`/Swift 6 mode are still lane A's to do.
  - `make build` and `make test SIM="Jimmy Lane 5"` both green after the sweep.
  - Combined: with `DIContainer`/`GRDBRepositories` gone, `MemoryCacheStore`/`MemoryCache`/`ShowMetadata` had no callers left and were deleted too, so `Domain/` and `Data/` are both gone.
- [ ] 26. Demo library + screenshots + README (H script, S seeding)
- [ ] 27. `docs/qa.md` and QA rounds (H)
- [ ] 28. Release guide, v8.0 tag (H)
- [ ] 29. Going public, each step approved by Chen (main session)

## Only Chen
- Export `jimmy.db` from the phone (PR 7).
- Real-device check of the real library (PR 9b).
- Go-ahead for each step of PR 29.

## Review

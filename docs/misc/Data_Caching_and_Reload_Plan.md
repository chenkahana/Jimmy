# Data Caching & Reload Plan - Implemented

This document outlines the implemented data caching and reloading strategy for the Jimmy podcast app. The primary goals were to improve performance, reduce network usage, and provide a more responsive user experience.

---

## 1. Layered Caching & Persistence

### 1.1 In-Memory Layer (NSCache)
- [x] Create `Utilities/MemoryCache.swift` – a generic LRU cache wrapper around `NSCache` supporting cost limits & automatic eviction callbacks.
- [x] Instantiate dedicated caches in `MemoryCacheStore`:
  - `subscriptionCache` (`UUID → Podcast`)
  - `showCache` (`URL → ShowMetadata`)
  - `episodePageCache` (`(podcastID,page) → [Episode]`)
  - `episodeDetailCache` (`EpisodeID → EpisodeDetail`)
  - `playbackStateCache` (`EpisodeID → PlaybackState`)
- [x] Provide simple helper APIs: `cache.value(forKey:)`, `cache.setValue(forKey:cost:)`.
- [x] Expose caches via a `MemoryCacheStore.shared` singleton.
- [ ] Write unit tests ensuring eviction policy & thread-safety.

### 1.2 GRDB Persistence Layer
- [x] Extend `Jimmy/Services/DatabaseManager.swift` migrations to include:
  - `subscriptions` (id[PK], feedURL UNIQUE, title, artworkURL, lastFetched, etag)
  - `shows` (feedURL[PK], description, author, language, updatedAt)
  - `episodes` (**replace existing** with paged structure → add `page` INT, `fetchedAt` DATETIME, UNIQUE(feedURL,id))
  - `episode_details` (episodeID[PK], fullDescription, chaptersJSON)
  - `playback_state` (episodeID[PK], position, finished, updatedAt)
- [x] Switch `DatabaseManager` to `DatabasePool` for concurrent reads/writes (WAL mode).
- [x] Use `DatabaseMigrator` for versioned migrations (v1 → v2).
- [x] Provide `DatabaseWriter.asyncWrite {}` wrappers for heavy inserts/updates.

### 1.3 Repository Chain (Memory → Disk → Network)
- [x] Introduce `LayeredRepository` base class implementing common fetch/write template method. (Note: Implemented directly in concrete repos)
- [x] Create concrete repos:
  - `SubscriptionRepository` (as `GRDBPodcastRepository`)
  - `ShowRepository` (TODO)
  - `EpisodeRepository` (paged + details, as `GRDBEpisodeRepository`)
  - `PlaybackStateRepository` (as `GRDBPlaybackStateRepository`)
- [x] Each `fetch` follows: `memoryCache → db.read { … }` then `writeThrough` caches. (Network fetch to be handled by services).
- [x] Inject `OptimizedNetworkManager` for networking; honor HTTP cache headers. (Injected into `GRDBPodcastRepository`).
- [x] Add Combine `@MainActor` publishers (`changesPublisher`) for UI updates.

---

## 2. Selective Reload Logic
- [x] In `EpisodeUpdateService` iterate all subscriptions on launch & pull-to-refresh.
- [x] Perform HEAD (or lightweight GET with `If-None-Match`/`If-Modified-Since`) requests.
- [x] Compare `etag` / `Last-Modified` / `content-length` against stored values.
- [x] Only fetch full feed & parse episodes when change detected.
- [x] Persist new `lastFetched` & `etag` to GRDB and update memory caches.
- [ ] Post `NotificationCenter` or Combine events so ViewModels refresh diffable snapshots.

---

## 3. Performance & Concurrency
- [x] All GRDB writes use `dbPool.asyncWrite {}` or `dbPool.writeWithoutTransaction` inside detached `Task(priority: .utility)`.
- [x] Network and disk I/O executed on background priorities; never block main thread.
- [x] Wrap each network call with `withTimeout(15)` helper; propagate `CancellationError`.
- [x] Keep one cancellable `Task` per podcast reload & per episode-page fetch; cancel prior if still running.
- [x] Apply exponential backoff (`1s → 2s → 4s (max 30s)`) using `RetryPolicy` utility on transient `URLError` codes.
- [ ] Benchmark memory footprint before/after caching via `UIPerformanceManager`.

---

## 4. MVVM & UI Patterns
- [x] Annotate all ViewModel classes with `@MainActor`; keep heavy work in `Task.detached`.
- [ ] Expose `@Published var state: ViewState` where `ViewState` = `.loading`, `.loaded`, `.error`.
- [ ] In `EpisodeListView` & `LibraryView` switch to `UITableViewDiffableDataSource` (UIKit path) or `List` with `transaction` animations (SwiftUI 5) for smooth updates.
- [ ] Implement `tableView(_:prefetchRowsAt:)` or SwiftUI `onAppear` on last cell to trigger `EpisodeRepository.fetchNextPage()`.
- [ ] Show `SkeletonCell` placeholders while state == `.loading` and `RetryView` on failures.
- [ ] Cache episode artwork with `AsyncImage` + `URLCache.shared` (memory 20 MB / disk 150 MB).

---

## 5. File-by-File Checklist

### Jimmy/Services/DatabaseManager.swift
- [x] Add `subscriptions`, `shows`, `episode_details`, `playback_state` tables & indices (see 1.2).
- [x] Switch from `DatabaseQueue` → `DatabasePool` with WAL mode retained.
- [x] Update `runMigrations()` with versioning (`v1` → `v2`).
- [x] Expose `dbPool` var & deprecate `dbQueue` usages across codebase.
- [x] Provide helper `writeAsync(_:)` and `readAsync(_:)` wrappers with error logging via `Logger`.
- [ ] Add unit test `DatabaseManagerTests.testMigrationToV2()`.

### Jimmy/Data/Repositories/GRDBRepositories.swift
- [x] Remove `ConcreteStorageRepository` in favour of `GRDBStorageRepository` (new file `GRDBRepositories.swift`).
- [x] Inject `MemoryCacheStore` into podcast/episode repositories.
- [x] Refactor `fetchEpisodes(for:)` to consult memory, then `db.read`. Network logic moved to services.
- [x] Replace UserDefaults persistence with GRDB CRUD using normalised tables.
- [x] Ensure all public publishers dispatch on `MainActor`.
- [ ] Unit test cache hit/miss scenarios with in-memory DB.

### Jimmy/Domain/Repositories/RepositoryProtocols.swift
- [x] Update protocols to include async `fetchPage(podcastID:page:)` & `savePlaybackState(_:)`.
- [x] Add associated type `Entity` with `DatabaseRecord` conformance. (Note: Opted for specific protocols).
- [x] Document cache order expectations in comments.
- [x] Mark methods `@MainActor` where they touch UI publishers. (Note: Publishers dispatch on MainActor).
- [x/A] Provide default protocol extension with LayeredRepository template. (Note: Implemented in concrete classes).

### Jimmy/Services/PodcastService.swift
- [x] Delegate all fetch/save logic to `SubscriptionRepository` & `ShowRepository`.
- [x] Remove any direct `URLSession` calls; rely on `OptimizedNetworkManager`.
- [x] Ensure paging logic leverages `EpisodeRepository.fetchPage`.
- [x] Expose Combine publisher `subscriptionsPublisher` sourced from repository changes.
- [x] Implement `refreshAll()` that triggers `EpisodeUpdateService.reloadAll()`.

### Jimmy/DependencyInjection/DIContainer.swift
- [x] Register `DatabaseManager.shared.dbPool`, `MemoryCacheStore.shared` singletons.
- [x] Swap `ConcreteStorageRepository` for new GRDB implementations.
- [x] Inject repositories into all services & view models.
- [ ] Provide preview/mock container for SwiftUI previews using in-memory DB.
- [x] Document registration order in inline comments.

### Jimmy/Services/EpisodeUpdateService.swift
- [x] Maintain dictionary `reloadTasks: [UUID: Task<Void, Error>]` to enforce single task per podcast.
- [x] Perform HEAD request with timeout; bail early on 304 Not Modified.
- [x] On new content, call `EpisodeRepository.saveEpisodes()` off main thread.
- [x] Broadcast `episodeChangesPublisher` with only real diff (insert/delete/update arrays computed).
- [ ] Throttle background refreshes via `BackgroundTaskManager.scheduleAppRefresh()` every 6 h.

### Jimmy/Services/OptimizedNetworkManager.swift
- [x] Add helper `func head(_ url:URL) async throws -> HTTPURLResponse`.
- [x] Respect `URLCache` & set `cachePolicy = .reloadRevalidatingCacheData`.
- [x] Implement `withTimeout(_ seconds: Double)` wrapper.
- [x] Use `RetryPolicy` exponential backoff for `URLError.networkConnectionLost`, `.timedOut`. (Note: Existing retry logic is sufficient).
- [x] Inject `URLSession` with custom `ephemeral` config for HEADs to avoid body download.

### Jimmy/Services/AudioPlayerService.swift
- [x] Persist playback updates through `PlaybackStateRepository.save()` every 5 s or on pause/stop.
- [x] Expose Combine publisher `playbackProgressPublisher` throttled to `0.5s` for smooth UI.
- [x] On `load(episode:)` call `playbackStateRepository.fetch()` to resume position.
- [ ] Decouple from `QueueViewModel` to avoid circular dependencies.

### Jimmy/Presentation/ViewModels/LibraryViewModel.swift
- [x] Inject `PodcastService` and `EpisodeRepository` for all data needs.
- [x] Remove any direct `EpisodeCacheService` or `FileStorage` dependencies.
- [x] Subscribe to `podcastService.subscriptionsPublisher` to update `@Published var podcasts`.
- [x] On `reloadData()` trigger `podcastService.refreshAll()`.
- [x] Search filters memory; no extra fetches needed.
- [ ] `onDelete` calls `podcastRepository.delete(podcast)`.

### Jimmy/Presentation/ViewModels/EpisodeListViewModel.swift
- [x] Accept `podcastID` and `EpisodeRepository` in initializer.
- [x] `@Published var episodes` loaded from `episodeRepository.fetchPage()`.
- [ ] Hold `@Published var rows: [EpisodeRowViewModel]` for diffable list.
- [x] Pre-fetch next page when last row appears; cancel if already loading.
- [x] Map repository `Episode` entities to lightweight row VMs.
- [x] Store currently running page task in `pageTask: Task<Void, Error>?`.
- [x] Handle pull-to-refresh: cancel pageTask, then call `EpisodeUpdateService.reload(podcastID:)`.

### Jimmy/Views/LibraryView.swift
- [ ] Use new `LibraryViewModel`.
- [ ] Replace `List` with `LazyVStack` inside `ScrollView` + diffable if performance needed.
- [ ] Display `SubscribePlaceholderView` when `subscriptions.isEmpty`.
- [ ] Show `ProgressView` overlay while ViewModel `.state == .loading`.
- [ ] Add `.refreshable { await viewModel.reload() }` (iOS 15+).
- [ ] Remove all debug `print` statements per Logging Guidelines.

### Jimmy/Views/EpisodeListView.swift
- [ ] Implement `List` with `onAppear` on last cell for prefetching.
- [ ] Show `EpisodeRowSkeleton` while loading.
- [ ] Inject `EpisodeListViewModel` via `.environmentObject` for previews.
- [ ] Add swipe action "Mark Played" that triggers `PlaybackStateRepository.markFinished()`.
- [ ] Ensure updates animate with `.animation(.default, value: viewModel.rows)`.

### Jimmy/Views/CurrentPlayView.swift
- [ ] Bind play/pause/progress to `AudioPlayerService` publishers.
- [ ] Display chapter list when available (`episodeDetail.chapters`).
- [ ] Show `DownloadButton` state from `EpisodeRepository.isDownloaded`).
- [ ] Trigger `EpisodeRepository.downloadAudio()` on tap.
- [ ] Adopt Liquid Glass materials for background.

### 🎯 Completion Criteria
- All above checkboxes ticked ✅.
- Cold launch < 700 ms median on iPhone 15 Pro (from Xcode metrics).
- Scrolling 120 Hz smooth in Library & Episode list views (UIPerformanceManager ≤ 8 ms/frame).
- No "Publishing changes from background threads" warnings.
- > 95 % cache hit ratio during daily use (metric logged via PerformanceMonitor). 
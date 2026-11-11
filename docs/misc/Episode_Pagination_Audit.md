## Episode Pagination Audit

This audit outlines concrete verification/refactoring tasks to ensure the **Show Episodes** flow delivers a fast, memory-safe, cancellable, and animation-friendly paginated experience.

---

### Key Goals
1. Load first page instantly (memory/disk cache → network fallback)
2. Seamless pre-fetch of additional pages while scrolling
3. Cancel stale in-flight network requests on rapid scroll
4. Apply diffable data-source snapshots for buttery-smooth UI updates
5. Memory **and** disk caching for near-instant reloads
6. Visual loading indicators (skeletons / spinners)
7. Timeout, retry & graceful error handling

---

## File-by-File Checklist

### 1. `ShowEpisodesViewModel.swift`
- [x] Ensure `episodes` & `state` properties are annotated with `@Published` and mutated only inside `@MainActor` contexts.
- [x] Maintain **one** `paginationTask: Task<Void, Never>?` — cancel any existing task before launching a new page fetch.
- [x] Implement `loadFirstPage()` called from `.task` that first serves cached data then triggers network refresh.
- [x] Provide `func loadNextPageIfNeeded(currentIndex:)` that checks the last 5 items & starts page fetch when threshold reached.
- [x] De-duplicate requests by guarding when `isLoadingPage == true` or `hasMorePages == false`.
- [x] Bubble up service errors via `@Published var error: EpisodeLoadingError?` for the view to present.
- [x] Expose a `retry()` that resets error state & re-calls the failed cursor.
- [ ] Unit-test ViewModel: first-page load, pagination happy-path, rapid-scroll cancellation, error→retry cycle.

### 2. `PaginatedEpisodeService.swift`
- [x] Refactor `fetchPage(after cursor: String?) async throws -> EpisodePage` to leverage `async/await` and *15 s* timeout using `withTimeout(_:operation:)` helper.
- [x] Perform network work on a background QoS (`priority: .utility`).
- [x] Support **cancellation** by periodically checking `Task.isCancelled` & throwing `CancellationError()`.
- [x] Add exponential-backoff retries (`maxAttempts = 3`, delays 0s → 1s → 3s) on `URLError.timedOut` & 5xx server errors.
- [x] Decode & return `EpisodePage` (items + nextCursor) only after validating payload size & schema.
- [x] Tag each request with `requestID` & log (via `os.Logger`) start/finish/cancel for debugging.

### 3. `EpisodeCacheService.swift`
- [x] Verify **NSCache** is keyed by `podcastID + episodeID` with LRU size limits (e.g., 100 episodes ≈ ~5 MB).
- [x] Confirm disk-cache path is in `Caches/episodes/{podcastID}.json` & uses atomic writes.
- [x] Add `Task`-friendly `func loadPageFromDisk(cursor:) async throws -> EpisodePage?` that executes on `.background` queue.
- [x] Persist each successfully fetched page asynchronously; coalesce multiple writes to minimise IO churn.
- [x] Implement cache invalidation policy (e.g., expire after 24 h or when podcast feed updated).
- [ ] Unit tests: cold start load, warm cache hit, stale-data invalidation.

### 4. `PaginatedEpisodeListView.swift`
- [x] Call `viewModel.loadFirstPage()` in `.task` when the view appears.
- [x] Use `LazyVStack` (or `List`) with `onAppear` on row to trigger `viewModel.loadNextPageIfNeeded(currentIndex:)` when index is within last 5.
- [x] Show **skeleton rows** while `viewModel.isInitialLoading == true` (placeholders count = pageSize).
- [x] Overlay bottom **spinner** when `viewModel.isLoadingPage == true` & not initial.
- [ ] Animate insertions/removals using `withAnimation(.easeInOut)` or `transaction.animation = …`.
- [x] Guard against duplicate id collisions by ensuring `Episode.id` is `Hashable` & stable.
- [x] Present `ErrorView(retry:)` when `viewModel.error != nil`.

### 5. `EpisodeRowView.swift`
- [x] Make row independent & lightweight: avoid heavy image decoding on main thread; use `.task` for async image load.
- [x] Provide `redacted(reason:)` modifier to mirror skeleton state from parent.
- [x] Verify tapping row navigates without triggering extra page fetches.

### 6. `LoadingStateManager.swift`
- [x] Expose `enum LoadingState { case idle, firstPage, nextPage, error(EpisodeLoadingError) }` for consistent UI binding.
- [x] Provide `@MainActor` publishers so views can observe without additional Combine juggling.
- [x] Ensure state resets correctly after `retry()`.

### 7. `OptimizedNetworkManager.swift`
- [x] Confirm all API calls accept `timeoutInterval` & honour `URLSessionConfiguration.timeoutIntervalForRequest`.
- [x] Surface `TaskCancellationError` as `URLError.cancelled` for uniform handling upstream.
- [x] Add helper `func fetch<T: Decodable>(_: URL, type: T.Type) async throws -> T` that logs & instruments duration.
- [x] Validate requests are added to `URLSession.shared` with **ephemeral** configuration for privacy.

---

## Cross-Cutting Validations
- [x] **Cancellation**: Rapid scroll → old request should cancel (verify via logs / breakpoints).
- [x] **Skeleton/Spinner**: Initial skeleton, bottom spinner on pagination, hide on success/error.
- [x] **Timeout & Retry**: Simulate slow network (10 kb/s), ensure retry logic triggers and UI reflects progress.
- [ ] **Memory Leaks**: Use Instruments "Leaks" & "Allocations" to confirm ViewModel & Network tasks deallocate on view dismissal.
- [x] **Diffable Snapshots**: Snapshot application must occur on `MainActor`; no "collection view inconsistency" runtime warnings.
- [x] **Error UI**: Show unobtrusive banner + "Retry" button; retry cancels banner & relaunches failed task.
- [ ] **Performance**: Verify scrolling at 60 fps on iPhone SE (3rd gen) with 1k+ episodes paged in.
- [x] **Accessibility**: Loading indicators are VoiceOver-friendly & retry button labelled.

---

> Tick each box as you implement & validate. The checklist intentionally blends **code refactor tasks** and **QA steps** to guarantee a production-ready Show Episodes pagination experience. 
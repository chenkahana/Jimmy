# MVVM Health Audit

This document provides a file-by-file checklist to help you verify MVVM separation and multithreading best-practices throughout the code-base.  Tick each box as you audit the file.

Legend
- View checklist (V):  Main-thread UI • No business logic • Lightweight view • Observes ViewModel only • Cancels background tasks • Thread-safe UI
- ViewModel checklist (VM):  Async/await heavy work • Publishes on main thread • No direct UI code • Robust error handling • Cancels Combine tasks • Weak self in closures • Single responsibility
- Model / Service checklist (M):  No UI imports • Work off main thread • Async/await or callbacks • Returns results on main • Comprehensive error handling • Non-blocking (no sync/semaphores) • DI friendly

---

## View Layer

#### Jimmy/Views/ContentView.swift
- [x] Main-thread UI
- [x] No business logic
- [x] Lightweight view
- [x] Observes ViewModel only
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/LibraryView.swift
- [x] Main-thread UI
- [ ] No business logic  <!-- Contains Task blocks and data operations -->
- [x] Lightweight view
- [x] Observes ViewModel only
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/SettingsView.swift
- [x] Main-thread UI
- [ ] No business logic  <!-- Extensive business logic, file operations, debug prints -->
- [ ] Lightweight view  <!-- 64KB, too large -->
- [ ] Observes ViewModel only  <!-- Direct service calls -->
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/DiscoverView.swift
- [x] Main-thread UI
- [ ] No business logic  <!-- Contains Task blocks for data operations -->
- [x] Lightweight view
- [x] Observes ViewModel only
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/CurrentPlayView.swift
- [x] Main-thread UI
- [ ] No business logic  <!-- Audio player logic embedded -->
- [ ] Lightweight view  <!-- Large, complex state management -->
- [ ] Observes ViewModel only  <!-- Direct service calls -->
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/MiniPlayerView.swift
- [x] Main-thread UI
- [ ] No business logic  <!-- Player logic embedded -->
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [x] Cancels background tasks
- [x] Thread-safe UI

#### Jimmy/Views/TopChartRowView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/PodcastSearchView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/EpisodeDetailView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/QueueEpisodeCardView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/PodcastDetailView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/AppLoadingView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/TrendingEpisodeItemView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/RecommendedPodcastItem.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/FeedbackFormView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/LibrarySearchComponent.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/EpisodeArchitectureDebugView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/UndoToastView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/CachedAsyncImage.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/EpisodeListComponent.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/PodcastGridComponent.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/LiquidGlassTabBar.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/ExampleCachedImageUsage.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/FileImportNamingView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/LoadingIndicator.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/Components/BackgroundTaskDebugView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/AnalyticsView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/LargeRecommendedPodcastItem.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/EpisodeListView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/EpisodePlayerView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/QueueView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/EpisodeRowView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/CacheManagementView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/DiscoverGenreSectionView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/StorageDebugView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/PodcastListView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### Jimmy/Views/AudioPlayerView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### WatchFiles/WatchContentView.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

#### WatchFiles/JimmyWatchApp.swift
- [ ] Main-thread UI
- [ ] No business logic
- [ ] Lightweight view
- [ ] Observes ViewModel only
- [ ] Cancels background tasks
- [ ] Thread-safe UI

---

## ViewModel Layer

#### Jimmy/Presentation/ViewModels/CleanArchitectureViewModels.swift
- [x] Async/await heavy work
- [x] Publishes on main thread
- [x] No direct UI code
- [x] Robust error handling
- [x] Cancels Combine tasks
- [x] Weak self in closures
- [x] Single responsibility

#### Jimmy/Services/QueueViewModel.swift  <!-- MISPLACED: Should be in ViewModels directory -->
- [x] Async/await heavy work
- [x] Publishes on main thread
- [x] No direct UI code
- [x] Robust error handling
- [x] Cancels Combine tasks
- [x] Weak self in closures
- [x] Single responsibility
- [ ] Proper location (should be in ViewModels)

#### Jimmy/Services/LoadingStateManager.swift
- [ ] No UI imports  <!-- Imports SwiftUI, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/LibraryController.swift  <!-- Should be a ViewModel -->
- [x] No UI imports
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [ ] DI friendly (contains @Published properties, acts as ViewModel)

#### Jimmy/Services/UnifiedDiscoveryController.swift  <!-- Should be a ViewModel -->
- [x] No UI imports
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [ ] DI friendly (contains @Published properties, acts as ViewModel)

#### Jimmy/Services/UIPerformanceManager.swift
- [ ] No UI imports  <!-- Imports UIKit, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/CrashPreventionManager.swift
- [ ] No UI imports  <!-- Imports UIKit, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/AudioPlayerService.swift
- [x] No UI imports (AVFoundation/MediaPlayer only)
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [ ] DI friendly (singleton pattern overused)

#### Jimmy/Services/LoadingStateManager.swift
- [ ] No UI imports  <!-- Imports SwiftUI, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/LibraryController.swift  <!-- Should be a ViewModel -->
- [x] No UI imports
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [ ] DI friendly (contains @Published properties, acts as ViewModel)

#### Jimmy/Services/UnifiedDiscoveryController.swift  <!-- Should be a ViewModel -->
- [x] No UI imports
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [ ] DI friendly (contains @Published properties, acts as ViewModel)

#### Jimmy/Services/UIPerformanceManager.swift
- [ ] No UI imports  <!-- Imports UIKit, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/CrashPreventionManager.swift
- [ ] No UI imports  <!-- Imports UIKit, should not -->
- [x] Work off main thread
- [x] Async/await or callbacks
- [x] Returns results on main
- [x] Comprehensive error handling
- [x] Non-blocking (no sync/semaphores)
- [x] DI friendly

#### Jimmy/Services/ShakeUndoManager.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/BackgroundRefreshService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/iTunesSearchService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/EpisodeUpdateService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/SharedAudioImporter.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/OptimizedPodcastService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/EpisodeCacheService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PodcastStore.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/ApplePodcastService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/AppleEpisodeLinkService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/DiscoveryService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/EnhancedEpisodeController.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PodcastRecoveryService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PodcastURLResolver.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/FetchWorker.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PerformanceMonitor.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/OptimizedNetworkManager.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/UnifiedEpisodeController.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/SubscriptionImportService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/WatchConnectivityService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/EpisodeRepository.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/RecommendationService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/BackgroundTaskManager.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/UIUpdateService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/FeedbackService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PodcastService.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/EpisodeFetchWorker.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/PodcastDataManager.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### Jimmy/Services/DataFetchCoordinator.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

#### WatchFiles/WatchPlayerManager.swift
- [ ] No UI imports
- [ ] Work off main thread
- [ ] Async/await or callbacks
- [ ] Returns results on main
- [ ] Comprehensive error handling
- [ ] Non-blocking (no sync/semaphores)
- [ ] DI friendly

---

## Cross-Cutting Concerns Summary

- [x] **Error Handling:** All network / file-I/O calls surface errors via `throws` or `Result` and callers handle them gracefully.
- [x] **Threading:** Zero occurrences of `DispatchSemaphore.wait`, `DispatchQueue.main.sync`, or busy-wait loops across the code-base.
- [x] **Retain Cycles:** Combine / async closures use `[weak self]` to avoid memory leaks.
- [x] **Cancellation:** All `Task {}` and Combine publishers are cancelled in `deinit` / `onDisappear`.
- [ ] **Naming Consistency:** File & type names do not always reflect their MVVM layer and intent (e.g. some ViewModels live in Services).
- [ ] **Layering Violations:** Some Services import UI frameworks; some Views import and observe Services directly.
- [ ] **Singleton Overuse:** Global `.shared` is overused; DI should be preferred for testability.
- [ ] **Logging Discipline:** Excessive debug prints remain in some Views (especially SettingsView).

## Immediate Action Items
- Extract ViewModels from Services (LibraryController, UnifiedDiscoveryController, etc.)
- Remove UI imports from all Services
- Refactor massive Views (SettingsView, CurrentPlayView, MiniPlayerView)
- Remove business logic from Views (move to ViewModels)
- Clean up debug prints in Views
- Add missing ViewModels for Settings, AudioPlayer, Discovery, CacheManagement
- Standardize naming and file organization

<!-- Service files --> 
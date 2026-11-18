# R1 Inventory

Every surface Jimmy has on `main` (`601bfa4`), the states each one can be in, how you get in and out, the gestures it
answers to, and the VoiceOver path through it. "Seen" points at the capture under `~/tmp/codex/jimmy-craft/`;
"code" means the state exists in code but wasn't reached in the simulator.

## R1.1 Surfaces × states

| Surface | File | States | Seen |
|---|---|---|---|
| Shell (tabs + bottom accessory) | `Jimmy/Views/AppShell.swift` | Three tabs: Queue, Library, Search (`Tab(role: .search)`). Mini player shown only when an episode is loaded. `.tabBarMinimizeBehavior(.onScrollDown)`. Sheets: Settings, Add by URL, Stats, Feedback, local audio import. | `run-light/01-queue.png` |
| Mini player | `Views/Components/NowPlaying/NativeMiniPlayerView.swift` | Inline (art 28 pt, title, play) and expanded (art 36 pt, title, "N min left", play, skip forward). First-run TipKit popover "Jump back into now playing". | `run-light/01-queue.png`, `shots/queue-d1-s.png` |
| Queue | `Views/QueueView.swift`, `Views/Components/QueueEpisodeRow.swift` | Empty ("Queue Is Empty" + Browse Shows); list; current episode with animated waveform; in-progress with progress line; played (secondary title, "Played"); Edit mode (delete + reorder handles); AX sizes stack artwork above text. Footer summary "4 episodes · 2 h 32 min left". | `run-light/q-*`, `run/o-04-empty-queue.png` |
| Suggestions sheet | `Suggestions/SuggestionsView.swift` | Loading (centered spinner); empty ("Nothing to Suggest Yet"); list with Up Next and New Shows; unavailable note. | `run-light/q-10-suggestions.png` |
| Library | `Views/LibraryView.swift`, `LibraryShowCell.swift`, `LibrarySupportViews.swift` | Empty (EmptyStateView); loading (spinner replacing content when no shows yet); Shows grid; Episodes list (last 100, `LazyVStack` of `EpisodeCard`); search with no results; "Couldn't refresh N shows. Try Again." row; pull to refresh. | `run-light/l-00.png`, `l-01-episodes.png`, `run/o-05-empty-library.png` |
| Podcast detail | `Views/PodcastDetailView.swift`, `Components/PodcastHeader.swift`, `Components/PodcastEpisodeListView.swift` | Loading; loaded with hero, Follow/Following, description with More; episodes failed ("Couldn't Load Episodes" + Try Again); filter/sort menu (All, Unplayed, Downloaded…); Unfollow confirmation; scrolled with inline title. | `run-light/l-03-podcast.png`, `l-04-podcast-scrolled.png` |
| Episode detail | `Views/EpisodeDetailView.swift` | Header (art 120 pt, show, title, date · duration, progress); actions (Play/Pause, Add/Remove Queue icon, Download icon states); show notes (New York serif); Chapters, Transcript, Bookmarks subsections when present; Copy Apple Podcasts Link. | `run-light/q-07-*`, `q-08-*`, `l-05-episode.png` |
| Now Playing | `Views/Components/NowPlaying/ExpandedNowPlayingView.swift` | Nothing playing (ContentUnavailableView + Close); paused; playing; artwork-color backdrop or system background; scrubbing; panel open (Speed, Sleep presets, Sleep running, Chapters list / "no chapters"); More menu (download states). | `run-light/p-*` |
| Discover / Search | `Views/DiscoverView.swift`, `DiscoverSupportViews.swift`, `DiscoveryViewModel.swift` | Charts loading (skeleton rows); charts loaded (Top Shows numbered, + to follow, checkmark once followed); charts failed ("Couldn't Load Top Shows"); recent searches; typing (skeleton); results; no results (`ContentUnavailableView.search`); search result detail (`AsyncPodcastDetailView`); subscribe failure alert. | `run-light/d-*`, `sheets/d-tab.png` |
| Settings | `Views/SettingsView.swift` | Form: Playback, Appearance, Sync & Backup, Import & Export, Assistant, About, Developer, destructive actions with confirmations. Inline progress for backup/import. | `run-light/l-09..12-settings*.png` |
| Listening Stats | `Views/ListeningStatsView.swift` | Stats sheet (from More menu and Settings > Developer). | `run-light/l-13-stats.png` |
| Add Podcast by URL | `ManualImportView` | Sheet with URL field. | code |
| Send Feedback | `Views/FeedbackFormView.swift` | Form; sent (dismisses after a 1.5 s timer). | code |
| Assistant | `Views/AssistantView.swift` | Empty, thinking (spinner), conversation. | code |
| Onboarding | `Onboarding/OnboardingView.swift`, `ImportProgressView.swift` | Welcome list (installed apps first, other apps, Start Fresh); source steps (Choose File / Paste / Sign In with Spotify); import progress with artwork filling in; finished; failed + retry. | `run/o-*` |
| Launch failure | `Views/LaunchFailureView.swift` | Store couldn't open: message + reset. | code |
| Error banner | `Views/Components/ErrorBannerView.swift` | Transient banner with retry/dismiss. | code |
| CarPlay | `CarPlay/CarPlayManager.swift` | `CPTabBarTemplate`: Queue list, Library list → show list, Now Playing (`CPNowPlayingTemplate.shared`). | code, needs device |
| Watch | `JimmyWatch/` | Not reachable ("Open Jimmy on your iPhone"); vertical pages Now Playing / Queue / Recent; Nothing Playing; Queue Is Empty. | code, needs device |
| Lock Screen / Control Center | `Packages/JimmyKit/.../NowPlayingController.swift`, `RemoteCommandController.swift` | Title, show (artist and album), duration, elapsed, rate, artwork; play, pause, toggle, skip ± (preferred intervals from Settings), change position; next track disabled. | code, needs device |
| Widgets, Live Activity, Controls, App Intents, Spotlight, Handoff | — | None on `main` (`WidgetData.swift` model exists, no widget extension). | sweep |

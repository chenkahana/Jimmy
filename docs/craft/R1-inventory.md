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

## R1.2 Transitions and gestures

| From → to | Mechanism | Seen |
|---|---|---|
| Mini player → Now Playing | `fullScreenCover` (slide up). `NowPlayingNamespace` and `NowPlayingGeometryID` are defined but unused. | `sheets/p-open.png` |
| Now Playing → back | Chevron (`closePlayer`), or drag down past 100 pt (rubber band, no velocity), or system cover swipe. | `sheets/p-dismiss.png` |
| Now Playing panels | `BottomPanel` slides up with `.snappy(0.3)` (fade under Reduce Motion); dismiss by tapping the dimmed player, dragging down > 80 pt or flicking (`predictedEndTranslation` > 220), VoiceOver escape. | `run-light/p-04..08` |
| Queue row → Episode detail | Push with `.navigationTransition(.zoom)` from the row. | `run-light/q-07-*` |
| Library tile → Podcast | Push with zoom from the tile; hero artwork and backdrop color load after the push. | `sheets/l-zoom.png` |
| Library episode → Episode detail | Push with zoom. | `run-light/l-05-episode.png` |
| Discover row/result → Podcast | Push with zoom (`matchedTransitionSource`). | `run-light/d-05-*` |
| Tabs | System `TabView`; tab bar minimizes on scroll down. | all |
| Sheets (Settings, Stats, Add by URL, Feedback, Suggestions) | System sheets, swipe down to dismiss. Settings and Stats have Done; Suggestions has none. | `run-light/l-09`, `q-10` |
| Onboarding | `fullScreenCover`, `interactiveDismissDisabled`; Skip → Library; Browse Top Shows → Search. | `run/o-*` |

| Surface | Gestures |
|---|---|
| Queue row | Tap → detail; play button; leading swipe (Play Next, Mark Played/Unplayed); trailing swipe (Remove, Download/Cancel/Remove Download); long-press context menu (Play/Pause, Play Next, Move to End, Mark Played, Download, Remove); Edit → drag handles and delete. |
| Library Episodes card | Tap → detail; play; trailing swipe shows one blue "Played" action (no Remove, no Add to Queue on the leading edge unless wired); context menu Play, Add to Queue, Mark as Played (`Components/EpisodeCard.swift:50-66`). Seen: `run/s-00..02`. |
| Podcast episode row | Tap; leading/trailing swipe; context menu (`PodcastEpisodeListView.swift:65-74`). Filter and Sort menu: All Episodes / Unplayed / Played, Newest / Oldest First (`run/s-07-filter-sort.png`). |
| Show tile | Tap → podcast (zoom); context menu with only "Unsubscribe" (plus a DEBUG-only "Unsubscribe from All") and an "Unsubscribe" VoiceOver action (`LibraryView.swift:296-309`). Seen: `run/s-03-show-context.png`. |
| Now Playing | Scrubber drag (plain `Slider`); transport taps; drag down anywhere on the player; panels drag down. |
| Discover | Pull nothing (no refresh on charts); swipe to delete recent searches. |
| Library | Pull to refresh. |

## R1.3 VoiceOver paths

From the accessibility trees (`*.ax.txt`), in reading order:

- **Queue:** nav "Queue" → Edit → each row as one button ("Know the Score, 99% Invisible, 26 min left, 1d, Paused",
  value "32%") with a separate "Play" button inside it, and a "Pause/Play" custom action → summary text → More,
  Suggestions → tabs Queue/Library/Search → mini player ("Know the Score, 26 min left", hint "Opens Now Playing")
  → Play → Skip Forward. Row hint "Shows episode details". The row adds one custom action (Play/Pause,
  `QueueView.swift:152`); the swipe actions reach VoiceOver through the system's Actions rotor, the context menu
  through "Show menu". The nested "Play" button is a second stop on every row.
- **Now Playing:** "Close Now Playing" → "More" (plus an unlabeled button at the same frame) → artwork ("Artwork for
  Know the Score from 99% Invisible", image) → title → show → "Playback position, 12:00 of 37:01" (adjustable: swipe
  up/down skips by the skip interval) → "Skip back 15 seconds" → "Play" → "Skip forward 15 seconds" → "Playback
  speed, 1×" → "Sleep timer" → "Chapters" → "AirPlay". Elapsed/remaining labels are hidden (the slider value covers
  them). Panels are modal with an escape action.
- **Podcast:** title, author, "Following", description, "More", "Episodes", each episode as one button ("Are wildfires
  making the future uninsurable?, Unplayed, 14 Nov · 41 min"); back button has an identifier but no label; "Filter
  and Sort".
- **Discover:** search field "Shows", "Top Shows", each chart row, + buttons.
- **Settings:** standard `Form` — labels, toggles and pickers read correctly.
- No custom rotors (headings exist on `JimmySectionHeader` and the Now Playing panel titles). No announcements:
  `AccessibilityService.announce(_:)` (`Services/AccessibilityService.swift:30`) exists but nothing calls it, so
  downloads finishing or failing, a sleep timer ending and errors are silent.

## R1.4 Coverage gaps in this inventory

Not reachable in the simulator and listed as "needs Chen device" in R0.3: CarPlay, Watch, Lock Screen / Control
Center / Dynamic Island, AirPods gestures and route changes, interruptions (calls, Siri), and 120 Hz smoothness.

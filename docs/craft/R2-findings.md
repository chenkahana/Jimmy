# R2 Findings

Every surface through the 12 rubric checks. Each finding has evidence (paths under `~/tmp/codex/jimmy-craft/`, or
`file:line` on `main` `601bfa4`), the rubric check it fails, severity × reach ÷ effort, and the product constraint it
touches. Scores use S1=4, S2=3, S3=2, S4=1; every session=4, daily=3, occasional=2, rare=1; effort S=1, M=2, L=4.

Constraint key: **Q** queue-centric model, **P** private and on-device, **N** playback never interrupted by UI work,
**—** none. "Needs Chen" marks a fix that would change a constraint or a written design rule (`docs/design.md`).
"Verify" marks evidence from the Duo simulator or a synthetic gesture that should be confirmed on an iPhone.

Captures: `run-light/` (Light), `run-dark/` (Dark), `run/` (latest run: onboarding, swipes, AX5), `sheets/` (frame
strips and contact sheets), `video/`.

## R2.1 Shell: tab bar, mini player, launch

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-01 | Mini player Play and Skip Forward are glyph-sized hit targets: **14.7 × 16.7 pt** and **20 × 22 pt**. The buttons use `.buttonStyle(.plain)` with no frame or `contentShape`. | `run-light/01-queue.ax.txt` (Button `play.fill` {14.7, 16.7}); `Jimmy/Views/Components/NowPlaying/NativeMiniPlayerView.swift:40-56` | 4 | S1 | every session | S | **16** | — |
| J-02 | Cold launch shows a blank white window for ~1.75 s, then **"Queue Is Empty" with Browse Shows flashes** before the queue appears, with artwork placeholders filling in after. The queue starts as `[]` and the empty state renders until the first observation emits. | `sheets/launch-cold.png` (0.75 s tap → 2.5 s blank → 2.75 s empty state → 3.0 s rows); `video/launch-cold.mov`; `Jimmy/Views/QueueView.swift:12,64-76`; `JimmyApp.init` → `AppModel.open` on the main thread (`traces/launch.trace`, R0.4) | 1, 8, 11 | S2 | every session | M | **6** | N (store open happens before playback restores; keep that order) |
| J-03 | After closing Now Playing the mini player is missing for one frame and pops back. | `sheets/p-dismiss.png` (frame 1.0 s) | 1 | S3 | daily | M | 3 | — |
| J-04 | The first-run tip "Jump back into now playing" is a popover that covers the third and fourth queue rows until dismissed. | `shots/queue-d1-s.png`; `NativeMiniPlayerView.swift:62` | 8 | S4 | rare | S | 1 | — |
| J-05 | At AX5 the mini player shows "K…" for the title next to full-size Play and Skip glyphs: the title is unreadable and the controls crowd it out. | `run/ax5-00-queue.png`, `run/ax5-01-library.png` | 6 | S2 | occasional | M | 3 | — |

Passes: native `TabView` with `Tab(role: .search)`, bottom accessory with inline and expanded placements, tab bar
minimizes on scroll, mini player has a hint ("Opens Now Playing") and Play/Pause labels.

## R2.2 Queue

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-06 | Row Play button is **32.7 pt**, below 44 pt. | `run-light/01-queue.ax.txt` (`play.circle.fill` {32.7, 32.7}); `Jimmy/Views/Components/QueueEpisodeRow.swift:122-131` | 4 | S2 | every session | S | **12** | — |
| J-07 | Swipe actions are untinted gray capsules (Play Next, Mark Played, Remove's sibling Download); they read as disabled next to the tinted context menu and next to Library's blue "Played" swipe. | `run-light/q-01-swipe-leading.png`, `run-dark/q-01-*`; `run/s-00-library-episode-swipe-left.png`; `QueueView.swift:156-163` | 4, 7 | S3 | daily | S | 6 | Needs Chen: `docs/design.md` "one accent, three jobs" rules out per-action tints |
| J-08 | Long-press then drag on a row opens the context menu; the row doesn't lift into a reorder, though the code comment says "Long-press and drag (or Edit) reorders". Reorder works only in Edit mode. | `sheets/reorder.png`; `QueueView.swift:78-80` | 4 | S2 | daily | M | 4.5 | Q. Verify on device (synthetic drag) |
| J-09 | Remove (swipe and menu) and Clear All act immediately with no Undo; Clear All has no confirmation. A mistaken full swipe loses the episode's place in the queue. | `QueueView.swift:113-118, 270-274` | 8 | S2 | occasional | M | 3 | Q |
| J-10 | Suggestions opens a sheet with only a centered spinner, no Done button and no title content until it loads. | `run-light/q-10-suggestions.png`; `Jimmy/Suggestions/SuggestionsView.swift:28-40` | 8 | S3 | occasional | S | 4 | — |
| J-11 | VoiceOver stops twice per row: the row (with value "32%") and its nested Play button. | `run-light/01-queue.ax.txt` | 12 | S3 | daily | S | 6 | — |

Passes: plain `List` in play order, current episode marked by an animated waveform that honors Reduce Motion,
progress line, `monospacedDigit` metadata, AX-size layout that stacks artwork above text (`run/ax5-00-queue.png`),
summary footer, context menu matches swipes, edit mode with reorder handles, a drop haptic.

## R2.3 Library (Shows, Episodes, Downloads)

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-12 | There is no Downloads view. `docs/design.md` promises Shows / Episodes / Downloads; `main` has Shows and Episodes, and downloads appear only as a podcast filter and a smart playlist. Nowhere shows what's downloading, failed or using space. | `run-light/l-00.png`; `Jimmy/Views/LibraryView.swift:28-29`; `docs/design.md` "Library" | 8 | S2 | daily | M | 4.5 | P (offline listening) |
| J-13 | One action, three names: Queue says "Mark Played", the Library card's swipe says "Played", its context menu says "Mark as Played". "Add to Queue" uses `text.append` on the card and `text.badge.plus` in episode detail. | `run/s-00`, `run/s-02`; `run-light/q-01`; `Components/EpisodeCard.swift:54-66`; `EpisodeDetailView.swift:131` | 9 | S3 | daily | S | 6 | — |
| J-14 | Show tile context menu has only "Unsubscribe", while the podcast page says "Follow / Following" (and Settings "Clear All Subscriptions"). No Play Latest, Mark All Played or Share. | `run/s-03-show-context.png`; `LibraryView.swift:296-309` | 9, 4 | S3 | occasional | S | 4 | — |
| J-15 | First load with no shows yet: a centered spinner replaces the page. | `LibraryView.swift:223-227` | 8 | S4 | rare | S | 1 | — |

Passes: `.searchable` in the nav bar drawer with the prompt following the segment, adaptive grid that becomes one
column at AX sizes, "Couldn't refresh N shows. Try Again." with automatic grammar agreement (`inflect: true`),
pull to refresh, empty state "No Shows Yet" with Browse Shows and Add Sample Shows (`run/os-01-after-skip.png`).

## R2.4 Discover and Search

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-16 | Top Shows aren't cached between launches. When the chart fetch fails (2 of 4 launches here, on a working connection) the tab replaces its skeleton with "Couldn't Load Top Shows. Check your connection and try again." and no recent results. | `sheets/d-tab.png`; `run-light/d-00-immediate.png`; `Jimmy/Presentation/ViewModels/DiscoveryViewModel.swift:71-99` | 8 | S2 | daily | M | 4.5 | P (cache stays on device) |

Passes: native `.searchable` with recent searches, skeleton rows with `redacted(.placeholder)` while loading
(`run-light/d-03-typing.png`), `ContentUnavailableView.search` for no results (`d-06-no-results.png`), zoom into a
result, follow button turns into a checkmark.

## R2.5 Podcast and episode detail

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-17 | **Show notes lose their structure.** HTML tags are stripped with a regex that doesn't turn `<p>`, `<br>` or `<li>` into line breaks, and `<a>` link targets are dropped, so paragraphs and link lists run together ("…climate changeInside the insurance industry's destruction labEpisode 797: Flood Money…", "InstagramTikTokYouTubeFacebook"). | `run-light/q-08-episode-detail-scrolled.png`; `Jimmy/Utilities/StringExtensions.swift:61-70`; used by `EpisodeDetailView.swift:288` and `EpisodeRowView.swift:104` | 6 | S2 | daily | M | 4.5 | — |
| J-18 | Podcast page: the hero artwork is blank for ~0.2 s after the zoom lands, then the artwork-color backdrop fades in over 0.6 s, so the page visibly repaints after it arrives. | `sheets/l-zoom.png`; `Jimmy/Services/ArtworkColorExtractor.swift:29,54` (`easeInOut(0.6)`) | 1, 5 | S2 | daily | M | 4.5 | — |
| J-19 | Scrolled podcast page: the pinned "Episodes" header sits above the inline "Planet Money" title, and episode text shows through behind both. | `sheets/l04-top.png`, `run-light/l-04-podcast-scrolled.png` | 5 | S2 | daily | M | 4.5 | Verify on iPhone |
| J-20 | Same episode, two durations: Queue "42 min", detail "41 min". Queue rounds up, `EpisodeCard.durationText` rounds to nearest. | `run-light/01-queue.png` vs `q-07-episode-detail.png`; `QueueEpisodeRow.swift:150` vs `Components/EpisodeCard.swift:164-168` | 9 | S3 | daily | S | 6 | — |
| J-21 | Dates change format by screen: Queue "1d", Library Episodes "17 Nov", podcast list "11 Nov", episode detail "14 Nov 2026". | `run-light/01-queue.png`, `l-01-episodes.png`, `l-04-*`, `q-07-*`; `QueueEpisodeRow.swift:153-170`, `EpisodeDetailView.swift:109` | 9 | S3 | daily | S | 6 | — |

Passes: zoom from row/tile, serif show notes with linked timestamps, Follow as `.glassProminent` and Following as
glass, Unfollow confirmation, Filter and Sort menu, "Couldn't Load Episodes" with Try Again, title moves into the
nav bar on scroll.

## R2.6 Now Playing

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-22 | **Chrome hit targets are tiny:** Close chevron **17.7 × 10.3 pt**; "1×" 16.7 × 18, "Sleep" 39.7 × 18, "Chapters" 64.3 × 18. The 44 pt frames sit inside plain-style labels without a `contentShape`. | `run-light/p-00-open.ax.txt`; `ExpandedNowPlayingView.swift:122-128, 252-270` | 4 | S1 | every session | S | **16** | — |
| J-23 | **A flick doesn't close the player.** Dismiss needs a 100 pt drag; release velocity is ignored, and `.animation(.motion, value: dragOffset)` animates every finger update so the player trails the finger. | `run-light/p-11-after-flick-80pt.png` (still open after a fast 80 pt flick), `sheets/p-dismiss.png`; `ExpandedNowPlayingView.swift:75, 315-327` | 1 | S2 | every session | S | **12** | — |
| J-24 | Mini → full player is a `fullScreenCover` slide; nothing grows from the mini player and the dismissal doesn't return to it. `NowPlayingNamespace` / `NowPlayingGeometryID` exist for a morph but nothing uses them. The title, scrubber and transport also shift up ~16 pt between 0.3 and 0.5 s after the cover lands. | `sheets/p-open.png`; `Jimmy/JimmyApp.swift:147-163`; `Views/Components/NowPlaying/NowPlayingNamespace.swift` | 1 | S2 | every session | L | 3 | N |
| J-25 | Speed is a five-segment control (0.75, 1, 1.25, 1.5, 2×): no 0.5×, 1.75×, 2.5× or fine steps, and nothing dial-like. | `run-light/p-04-speed.png`; `ExpandedNowPlayingView.swift:33, 276-285` | 2 | S2 | daily | M | 4.5 | — |
| J-26 | No haptics or symbol motion on the transport: skip buttons don't animate or tick, setting a speed or a sleep timer gives no feedback. Only the scrubber's release ticks. | `ExpandedNowPlayingView.swift:221-250`; `sweeps/haptics.txt` | 2 | S3 | every session | S | **8** | — |
| J-27 | Scrubber is a plain `Slider`: no growth on touch, no fine-scrub, no chapter marks, the elapsed/remaining labels don't track the finger's target. | `run-light/p-02-scrubbed.png`, `p-03-scrub-vertical.png`; `ExpandedNowPlayingView.swift:170-213` | 2 | S3 | daily | M | 3 | — |
| J-28 | The Chapters button is always there; on most episodes it opens "This episode has no chapters." | `run-light/p-08-chapters.png`; `ExpandedNowPlayingView.swift:262` | 8 | S3 | daily | S | 6 | — |
| J-29 | The ••• menu holds one item (Download). No Go to Show, Go to Episode, Share, Mark Played, Play Next. | `run-light/p-09-more.png`; `ExpandedNowPlayingView.swift:130-144` | 4, 10 | S3 | daily | S | 6 | — |
| J-30 | An unlabeled button sits at the same frame as "More": VoiceOver lands on a nameless element. | `run-light/p-00-open.ax.txt` (two Buttons at {326, 0, 44, 44}, one without a label) | 12 | S2 | daily | S | 9 | — |
| J-31 | Sleep panel: "Cancel Timer" wraps onto two lines inside its bordered button. | `run-light/p-07-sleep-set.png`; `SleepTimerView.swift:56` | 5 | S3 | occasional | S | 4 | — |

Passes: artwork-color backdrop that drops to the system background when it can't reach 4.5:1, secondary text at
full strength on color, Play/Pause `contentTransition(.symbolEffect(.replace))`, 72 pt play button, glass
transport capsule, adjustable scrubber for VoiceOver ("12:00 of 37:01"), AirPlay route picker, shared bottom panel
with tap-out, drag-to-dismiss and VoiceOver escape, Reduce Motion fade for panels.

## R2.7 Settings, Stats, Import, Feedback

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-32 | Names drift: "Send Feedback" (menu) vs "Submit Feedback" (Settings); "Follow/Following" vs "Clear All Subscriptions", "Couldn't Subscribe", "Subscribe to a few shows"; four overlapping backup/export items (Export Full Backup, Import Backup, Export App Data, Import JSON File); "Listening Stats" under a "Developer" section and in the More menu; three-dot "..." in progress strings ("Calculating...", "Reading JSON file..."). | `run-light/l-08-more-menu.png`, `l-09..12-settings*.png`; `AppShell.swift:76`; `DiscoverView.swift:61`; `Suggestions/SuggestionsView.swift:51`; `Presentation/ViewModels/SettingsViewModel.swift:66, 487, 508` | 9 | S3 | occasional | S | 4 | — |
| J-33 | Feedback form closes itself on a 1.5 s timer after sending. | `Jimmy/Views/FeedbackFormView.swift:61` | 11 | S4 | rare | S | 1 | — |

Passes: `Form` with section footers explaining settings, destructive actions last and red, version shown once in
About.

## R2.8 Onboarding

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-34 | "Choose an Export File" floats over the last source row with no material behind it; the row's subtitle is cut under the button at rest. | `run/o-00.png`, `run-dark/o-*` | 5 | S4 | rare | S | 1 | — |

Passes: one screen, installed apps first, what each source brings over, Skip in the toolbar, Start Fresh with a
footer, Skip lands on an empty Library with Browse Shows and Add Sample Shows (`run/os-01-after-skip.png`).

## R2.9 CarPlay, Watch, widgets, system integration

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-35 | Jimmy isn't a system citizen yet: **0** App Intents, widgets, Control Center controls, Live Activities, Spotlight items, `NSUserActivity` (Handoff) or `SceneStorage`. "Play my queue" from Siri or a Lock Screen widget isn't possible. | `PLAN.md` starting-evidence table (sweep on `main`) | 10 | S2 | daily | L | 2.25 | P (Handoff and Spotlight stay on device; needs Chen for Handoff) |
| J-36 | State restoration covers the player but not the place: after the app is killed on Planet Money's episode list in Library, relaunch opens the Queue tab at the top. The loaded episode and position do come back. | `run/r-00-before-kill.png`, `run/r-01-after-relaunch.png` | 10 | S3 | daily | M | 3 | — |
| J-37 | Lock Screen / Control Center: no chapter info in Now Playing info, no playback-rate command, next-track disabled (so AirPods "next" and CarPlay's next do nothing). | `Packages/JimmyKit/Sources/JimmyKit/Playback/NowPlayingController.swift:21-32`, `RemoteCommandController.swift:45`; device steps in R0.3 | 3 | S3 | daily | M | 3 | Q (what "next" means in a queue), needs Chen device |
| J-38 | CarPlay lists are text only (no artwork, no progress) and Now Playing has no rate button. | `Jimmy/CarPlay/CarPlayManager.swift:60-115` | 3 | S3 | daily | M | 3 | Needs Chen device |
| J-39 | Watch: skip glyphs hard-coded to 15 s whatever the phone's Settings say; queue rows use `onTapGesture` (VoiceOver doesn't call them buttons); "Nothing Playing" vs the phone's "Nothing Is Playing"; no artwork. | `JimmyWatch/Views/NowPlayingView.swift:24-36`, `QueueView.swift:14-18` | 3, 9, 12 | S3 | occasional | S | 4 | Needs Chen device |

## R2.10 Accessibility pass

Dynamic Type at AX5 (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`,
`run/ax5-*`), VoiceOver order from the accessibility trees, Reduce Motion and Reduce Transparency from code.
Increase Contrast via `simctl ui increase_contrast` wasn't captured separately; Jimmy also has its own "High
Contrast Mode" toggle (`HighContrastModifier.swift`).

| ID | Finding | Evidence | Check | Sev | Reach | Effort | Score | Constraint |
|---|---|---|---|---|---|---|---|---|
| J-40 | 22 fixed `.font(.system(size:))` sizes that don't scale, including status badges at 10 pt and the error banner at 12–16 pt. | `sweeps/fixedfont.txt`; `Components/StatusBadge.swift:21,38,54`; `Components/ErrorBannerView.swift:29-112` | 6 | S2 | occasional | S | 6 | — |
| J-41 | No VoiceOver announcements: `AccessibilityService.announce(_:)` exists but nothing calls it, so downloads finishing or failing, the sleep timer ending and errors are silent. | `Jimmy/Services/AccessibilityService.swift:30`; `rg announce` | 12 | S2 | occasional | S | 6 | — |
| J-42 | The loading shimmer (`LiquidSkeletonView`) runs `repeatForever` animations without checking Reduce Motion. | `Views/Components/LiquidSkeletonView.swift:277-282` | 1, 12 | S3 | occasional | S | 4 | — |

Passes: queue rows and Library reflow at AX5; Now Playing glyphs use `@ScaledMetric` with caps; the scrubber is
adjustable; panels are modal with escape; Reduce Motion handled for the waveform and panels; system glass handles
Reduce Transparency on its own (no custom blur to replace). See J-05 (mini player at AX5), J-11 and J-30
(VoiceOver).

## R2.11 Coverage by the existing polish docs

The handoff lists six docs; none are on `main` (they live only in the stale `~/Jimmy` checkout on
`feat/stability-first-overhaul`). They describe the pre-rewrite app:

| Doc | What it covered | Status on `main` |
|---|---|---|
| `world-class-native-polish-v3.md` | A custom "V3" Liquid Glass tab bar (`TabBarModelsV3`, `LiquidGlassTabBarContainerV3`), its Dynamic Type, Reduce Motion/Transparency, VoiceOver and 60/120 fps targets | Superseded: `main` uses the system `TabView` with `Tab(role: .search)` and a bottom accessory. Nothing to carry over. |
| `liquid-glass-design-tokens.md` | Tab-bar tokens (bar metrics, capsule, search pill, animation) | Superseded by `JimmyDesign` (`DesignSystem.swift`) and `docs/design.md`. R4 reconciles the remaining tokens. |
| `native-liquid-glass-migration.md` | Feature-flagged move to the native tab bar, rollback plan | Done: native tab bar shipped. |
| `split-capsule-tab-bar.md` | Two-capsule tab bar with a separate search capsule, spring parameters | Superseded by the system search tab. |
| `IMPROVEMENT_OPPORTUNITIES.md` | Service consolidation, architecture, performance roadmap | Not polish; mostly done by the JimmyKit rewrite. No overlap with R2. |
| `CURRENT_STATE_ASSESSMENT.md` | Health score, service analysis, bottlenecks | Same; stale. |

`docs/design.md` on `main` is the live design spec. Findings that touch it: J-07 (swipe tints vs one accent),
J-12 (Downloads segment promised, missing), J-24 (no morph despite "zoom transitions"), the Motion row in its token
table (R4.1), and its Words rule "Title-case labels" (J-32). None of the R2 findings were already fixed by earlier
polish work.

## R2.12 Craft scores (0–3 per check)

0 missing or broken · 1 present but rough · 2 good, small gaps · 3 Apple-level. Blank = check doesn't apply.

| Surface | 1 Motion | 2 Playback | 3 System | 4 Touch | 5 Geometry | 6 Type | 7 Color | 8 States | 9 Words | 10 Citizen | 11 Speed | 12 A11y |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Shell / mini player | 1 | 2 | | 0 | 2 | 1 | 3 | 1 | 2 | | 1 | 1 |
| Queue | 2 | | | 1 | 3 | 3 | 2 | 2 | 2 | | 2 | 2 |
| Library | 2 | | | 2 | 2 | 2 | 3 | 1 | 1 | | 2 | 2 |
| Discover / Search | 2 | | | 2 | 3 | 2 | 3 | 1 | 2 | | 2 | 2 |
| Podcast detail | 1 | | | 2 | 1 | 2 | 2 | 2 | 2 | | 2 | 2 |
| Episode detail | 2 | | | 2 | 2 | 1 | 3 | 2 | 1 | | 2 | 2 |
| Now Playing | 1 | 1 | 2 | 0 | 2 | 2 | 3 | 2 | 2 | | 2 | 1 |
| Settings / Stats | 2 | | | 3 | 3 | 3 | 3 | 2 | 1 | | 2 | 3 |
| Onboarding | 2 | | | 3 | 2 | 3 | 3 | 3 | 3 | | 2 | 2 |
| CarPlay | | 1 | 1 | | | | | | | 1 | | |
| Watch | | 1 | 1 | 1 | | | | 2 | 1 | 1 | | 1 |
| Widgets / Intents / Spotlight | | | 0 | | | | | | | 0 | | |

Average of 96 scored cells: **1.83** (out of 3). Lowest columns: Touch (hit targets), Motion (player and pop-in),
States (launch, Discover), Words (naming drift), System citizen.

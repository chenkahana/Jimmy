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
| J-28 | The Chapters button is always there; on most episodes it opens "This episode has no chapters." | `run-light/p-08-chapters.png`; `ExpandedNowPlayingView.swift:264` | 8 | S3 | daily | S | 6 | — |
| J-29 | The ••• menu holds one item (Download). No Go to Show, Go to Episode, Share, Mark Played, Play Next. | `run-light/p-09-more.png`; `ExpandedNowPlayingView.swift:130-144` | 4, 10 | S3 | daily | S | 6 | — |
| J-30 | An unlabeled button sits at the same frame as "More": VoiceOver lands on a nameless element. | `run-light/p-00-open.ax.txt` (two Buttons at {326, 0, 44, 44}, one without a label) | 12 | S2 | daily | S | 9 | — |
| J-31 | Sleep panel: "Cancel Timer" wraps onto two lines inside its bordered button. | `run-light/p-07-sleep-set.png`; `SleepTimerView.swift:62` | 5 | S3 | occasional | S | 4 | — |

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

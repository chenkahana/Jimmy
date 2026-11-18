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

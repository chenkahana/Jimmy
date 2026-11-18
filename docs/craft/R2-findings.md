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

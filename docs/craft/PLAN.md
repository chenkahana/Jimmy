# Jimmy craft research: plan and checklist

Research and docs only. No app code changes in this branch. Stop after R5; nothing gets implemented until Chen
approves the backlog. Resume point and log: [`PROGRESS.md`](PROGRESS.md).

- Repo: `chenkahana/Jimmy`, branch `docs/craft-research` off `main` at `601bfa4` (2026-11-13).
- Worktree: `~/.worktrees/Jimmy/craft-research`.
- Large evidence (recordings, traces, full-size screenshots): `~/tmp/codex/jimmy-craft/` on Chen's Mac, referenced
  by path. Only small essential screenshots go in git.
- Sister research: Boaz (`~/Boaz/tasks/ux-polish-plan.md`) and Edison use the same rubric and scoring.

## Checklist

### R0 Baseline → [`R0-baseline.md`](R0-baseline.md)
- [x] R0.1 Build and run in the simulator
- [x] R0.2 Recordings per flow: launch, queue, library, discover/search, podcast + episode detail, mini ↔ full
      player, scrub/speed/sleep, downloads, settings, onboarding (Light and Dark)
- [x] R0.3 System checks: Lock Screen / Control Center (Now Playing), CarPlay, Watch
- [x] R0.4 Instruments traces: launch, list scroll, player open/close, scrubbing
- [x] R0.5 Write `R0-baseline.md`

### R1 Inventory → [`R1-inventory.md`](R1-inventory.md)
- [x] R1.1 Surfaces × states
- [x] R1.2 Entry/exit transitions and gestures
- [x] R1.3 VoiceOver paths
- [x] R1.4 Write `R1-inventory.md`

### R2 Audit → [`R2-findings.md`](R2-findings.md)
- [x] R2.1 Shell: tab bar, mini player, navigation
- [x] R2.2 Queue
- [x] R2.3 Library (Shows, Episodes, Downloads)
- [x] R2.4 Discover and Search
- [x] R2.5 Podcast and episode detail
- [x] R2.6 Now Playing (full player, scrub, speed, sleep, chapters)
- [x] R2.7 Settings, Stats, Import, Feedback
- [x] R2.8 Onboarding
- [x] R2.9 CarPlay, Watch, widgets, system integration
- [x] R2.10 Accessibility pass: Dynamic Type AX5, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast
- [ ] R2.11 Mark coverage by the existing polish docs
- [ ] R2.12 Craft score table (surface × check, 0–3)

### R3 References → [`R3-references.md`](R3-references.md)
- [ ] R3.1 Apple Podcasts
- [ ] R3.2 Overcast
- [ ] R3.3 Pocket Casts
- [ ] R3.4 Castro
- [ ] R3.5 Apple Music (player)

### R4 Systems → [`R4-systems.md`](R4-systems.md)
- [ ] R4.1 Motion tokens
- [ ] R4.2 Haptic map
- [ ] R4.3 Layout tokens (spacing, radius, concentricity)
- [ ] R4.4 Type ramp
- [ ] R4.5 Copy rules and English String Catalog
- [ ] R4.6 State kit (empty, loading, offline, error)

### R5 Backlog → [`R5-backlog.md`](R5-backlog.md)
- [ ] R5.1 Score every finding
- [ ] R5.2 Group into workstreams
- [ ] R5.3 Slice into one-visible-change PRs, mark "needs Chen"

---

## Task

Find every small thing that keeps Jimmy from feeling like an app Apple would ship on iPhone, Apple Watch and
CarPlay, and turn it into a scored, sequenced backlog for Chen to approve.

**Product constraints polish must not break:** queue-centric model, private and on-device, playback that never
stops or skips because of UI work. A fix that would change any of these is marked "needs Chen".

**Runtime first.** Every backlog item needs a recording, screenshot or Instruments trace from the simulator or a
device. Code sweeps only point at where to look. Things that need hardware (CarPlay head unit, AirPods gestures,
Watch) are listed as "needs Chen device" with exact steps.

**Every finding records:** evidence (recording path, screenshot, trace, or `file:line`), rubric check, surface,
severity × reach ÷ effort, constraint touched.

## Starting evidence (re-run on `main` at `601bfa4`, 2026-11-18)

The handoff's numbers came from the stale `523eb26` checkout (the pre-rewrite app). `main` is a different, much
smaller app (293 Swift files incl. JimmyKit and Watch).

| Signal | Stale `523eb26` | `main` `601bfa4` |
|---|---|---|
| `withAnimation` / `.animation(` | 236 | 31 |
| `matchedGeometryEffect` / zoom transitions | 8 | 9 |
| Haptics (`sensoryFeedback` / `FeedbackGenerator`) | 39 | 11 |
| `accessibilityReduceMotion` | – | 5 |
| `accessibilityReduceTransparency` | – | 0 |
| `accessibilityLabel` | – | 39 |
| `.font(.system(size:))` | 127 | 22 |
| `@ScaledMetric` | 0 | 5 |
| `ContentUnavailableView` | 0 | 17 |
| `Task.sleep` / `asyncAfter` | 94 | 26 |
| `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` | 5 | 7 |
| `ActivityKit` | 0 | 0 |
| `AppIntent` | – | 0 |
| `WidgetKit` / `ControlWidget` | – | 0 / 0 |
| `keyboardShortcut` | 0 | 0 |
| `NSUserActivity` / `CSSearchable` | 0 | 0 |
| `String(localized:)` | 0 | 0 |
| `swipeActions` / `contextMenu` | – | 10 / 6 |
| `monospacedDigit` | – | 16 |
| `SceneStorage` | – | 0 |
| `accessibilityAdjustableAction` | – | 1 |

Distinct curves on `main`: `.snappy(duration: 0.3)` ×3, `.spring(response: 0.6, dampingFraction: 0.8)` ×2,
`.spring(response: 0.5, dampingFraction: 0.8)` ×2, `.easeInOut(duration: 0.6)` ×2, `.easeInOut(duration: 0.2)` ×2,
and one each of `.spring(0.4, 0.8)`, `.spring(0.38, 0.82)`, `.spring`, `.snappy(0.25)`, `.linear(1.5)`, `.linear`,
`.easeOut(0.2)`, `.easeInOut(2.0)`, `.easeInOut(0.3)` and two computed durations: 16 distinct curves for 31 sites.

Re-run with:
```sh
for p in 'withAnimation|\.animation\(' 'matchedGeometryEffect|navigationTransition|matchedTransitionSource' \
  'sensoryFeedback|FeedbackGenerator' 'accessibilityReduceMotion' 'accessibilityReduceTransparency' 'accessibilityLabel' \
  '\.font\(\.system\(size' 'ScaledMetric' 'ContentUnavailableView' 'Task\.sleep|asyncAfter' \
  'MPNowPlayingInfoCenter|MPRemoteCommandCenter' 'ActivityKit' 'AppIntent' 'String\(localized'; do
  printf "%-62s %s\n" "$p" "$(rg -c "$p" -g '*.swift' . | awk -F: '{s+=$2} END{print s+0}')"; done
rg -o '\.(spring|snappy|bouncy|smooth|easeInOut|easeOut|easeIn|linear)(\([^)]*\))?' -g '*.swift' . | sed 's/^[^:]*://' | sort | uniq -c | sort -rn
```

## Rubric: what makes an iPhone app feel like an iPhone app

Answer each check yes/no on every surface (tab bar, queue, library, discover, search, podcast and episode detail,
mini player, full player, downloads, stats, settings, onboarding, CarPlay, Watch, widgets).

1. **Motion with physics and one voice.** A small set of named curves. The mini player grows into the full player
   and back along the same path; artwork morphs from list to detail; a drag-to-dismiss player follows the finger,
   is interruptible, keeps release velocity and rubber-bands. No animation on content that was already there at
   launch. Zero hitches at 120 Hz in the main flows. Reduce Motion turns movement into fades.
2. **Playback feels physical.** Scrubbing has fine-scrub on vertical drag and haptic detents at chapter marks;
   play/pause responds within one frame with a symbol transition; skip buttons show the interval and animate;
   speed and sleep-timer controls feel like dials, not forms.
3. **The system plays along.** Lock Screen and Control Center show artwork, chapter, correct elapsed time and
   rate; remote commands (skip intervals, change playback position, like, rate) all work; AirPods gestures and
   route changes pause and resume correctly; interruptions (calls, Siri, other audio) recover; AirPlay route picker
   is where users expect it; CarPlay templates are complete and fast; the Watch shows the queue and controls.
   Live Activity / Dynamic Island for playback and long downloads is considered.
4. **Touch.** 44 pt targets; press states within one frame; swipe actions with full-swipe and matching context
   menus; context-menu previews on episodes and shows; reorder in the queue with lift, haptic and auto-scroll.
5. **Geometry.** Concentric continuous corners on artwork, cards and glass; one spacing and radius scale; artwork
   never stretches or pops in; nothing clips at the largest Dynamic Type or longest title.
6. **Type.** System text styles so Dynamic Type works up to AX5; tabular digits for times, durations and counts;
   episode titles truncate sensibly; show notes render as readable rich text.
7. **Color and materials.** Artwork-derived tint that stays readable (4.5:1) in Light, Dark and Increase Contrast;
   glass with a solid fallback under Reduce Transparency; no tint that fights the artwork.
8. **Every state designed.** Empty queue, empty library, no results, offline (with downloaded episodes still
   playable), feed failed to refresh, download failed or paused for cellular, first run, low storage. Loading under
   ~300 ms shows nothing; longer shows skeletons in place, not spinners replacing content.
9. **Words.** Title case for buttons, sentence case for descriptions; real ellipsis; one name per concept (Queue,
   Up Next, Library). English only (Chen, 2026-11-18): a String Catalog for copy review, plurals and grammar
   agreement, and `FormatStyle` for relative dates, durations and sizes; no translations.
10. **System citizen.** Widgets (Lock Screen and Home), Control Center control, App Intents and Siri ("Play my
    queue", "Skip 30 seconds"), Spotlight for shows and episodes, Handoff, state restoration (tab, scroll position,
    player state) after the app is killed.
11. **Speed.** Cold launch to a playable queue fast; scrolling long episode lists without hitches; images decoded
    off the main thread and cached; no timer-based waits in user-visible paths. Measured with Instruments.
12. **Accessibility.** VoiceOver can do everything, with an adjustable scrubber, custom actions on episode rows
    (play, queue, download, mark played), headers, rotors for long lists and announcements for downloads and
    errors; Voice Control names match visible labels; Accessibility Inspector audit clean.

## Phases

- **R0 Baseline:** build, run, record every main flow in Light and Dark; Instruments traces for launch, list
  scroll, player open/close and scrubbing.
- **R1 Inventory:** every surface × state × entry/exit transition × gesture × VoiceOver path.
- **R2 Audit:** every surface through the 12 checks; each finding with evidence, severity, effort, constraint
  touched; mark which items the existing polish docs already covered.
- **R3 References:** same flows in Apple Podcasts, Overcast, Pocket Casts and Castro (and Apple Music for the
  player). Mechanics (curve, duration, gesture, haptic, interruption), not looks.
- **R4 Systems:** motion tokens, haptic map, layout tokens, type ramp, copy rules, state kit.
- **R5 Backlog:** score, group into workstreams, slice into one-visible-change PRs, mark "needs Chen". Stop.

## Scoring (shared with Boaz and Edison)

Severity (S1 broken or inaccessible, S2 visibly unpolished in a main flow, S3 noticed by a careful user, S4 nit) ×
Reach (every session, daily, occasional, rare) ÷ Effort (S, M, L). Numeric: S1=4, S2=3, S3=2, S4=1; every
session=4, daily=3, occasional=2, rare=1; Effort S=1, M=2, L=4. Score = severity × reach ÷ effort.
Each surface also gets a craft score of 0–3 per rubric check.

## Done when

- `docs/craft/R0`–`R5` exist, every finding has evidence, and the backlog is ordered.
- Final report: repo and branch used and why, worktree path, top 10 findings, the systems proposal in five lines,
  and the questions only Chen can answer.

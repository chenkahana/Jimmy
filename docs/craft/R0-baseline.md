# R0 Baseline

Where the evidence came from, how to reproduce it, and what the app looks and feels like before any polish work.
Findings themselves live in [`R2-findings.md`](R2-findings.md); this file is the measurement setup and the raw
observations.

## R0.1 Build and run

| | |
|---|---|
| Code | `chenkahana/Jimmy` `main` `601bfa4` (2026-11-13) |
| Toolchain | Xcode 27.2, XcodeGen, iOS 27.1 simulator runtime |
| Build | `make project`, then `xcodebuild -project Jimmy.xcodeproj -scheme Jimmy -derivedDataPath build/DerivedData -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO build`: **BUILD SUCCEEDED** (log `~/tmp/codex/jimmy-craft/build.log`) |
| Simulator | "Jimmy Craft", device type iPhone Duo, iOS 27.1, udid `D3613924-57ED-4C71-8721-BA0DA2666DDA`. The `iPhone 17 Pro` simulator on this Mac only has iOS 26.4, which can't run an iOS 27 app, and iOS 27.1 only offers the iPhone Duo device type (as `CLAUDE.md` notes). All captures use the Duo's folded display (`--display=1`, 466 × 678 pt @3x). |
| Data | `-demoLibrary` (`Jimmy/App/DemoLibrary.swift`): six real public feeds (99% Invisible, This American Life, Planet Money, Radiolab, Hard Fork, Search Engine) and a four-episode queue with one episode in progress. Seeded once per `JIMMY_DEMO_DB_ID`. |
| Watch | No watchOS simulator runtime is installed, so the Watch app can't be run here. Needs Chen's device (see R0.3). |

**Duo caveat.** On the Duo's folded display iOS 27 puts the status bar and the tab bar in a vertical rail on the
trailing edge, and toolbar buttons stack under the status bar. That chrome is the system's, not Jimmy's; findings
only cover what Jimmy controls. Anything that depends on standard iPhone geometry (tab bar at the bottom, Dynamic
Island) is marked "verify on iPhone".

### How the flows are driven

`xcrun simctl` has no tap or swipe, and Jimmy's repo has no UI-test target in `project.yml` (`JimmyUITests/` is not
built). The flows run from a throwaway XCUITest project outside the repo (`~/tmp/codex/jimmy-craft/driver`) that
drives `com.chenkahana.Jimmy` by bundle ID, while `simctl io recordVideo --display=1` records. Each step also saves
the accessibility tree (`*.ax.txt`) and a screenshot, which give exact hit-target frames and VoiceOver labels.

```sh
~/tmp/codex/jimmy-craft/driver/run.sh <Class/testMethod> <video-name>
```

First run (`Dump/testDumpTabs`): launch, Queue, Library, Search all render with the demo library; no crash.
Screenshots and trees in `~/tmp/codex/jimmy-craft/run/0[0-4]-*`.

## R0.2 Flow recordings

Recorded on the Duo simulator's folded display with `simctl io recordVideo --codec=h264` while the driver ran each
flow. Simulator recordings are variable frame rate and capped by the host, so they show what moves and in which
order, not 120 Hz smoothness (that needs a ProMotion device; see R0.4). Frame strips cut from them with
`ffmpeg ... fps=10,tile` are the evidence quoted in R2.

All under `~/tmp/codex/jimmy-craft/`:

| Flow | What the driver does | Light | Dark | Stills + AX trees |
|---|---|---|---|---|
| Launch, tabs | Launch with demo library, Queue → Library → Search → Queue | — | — | `run-light/0[0-4]-*` |
| Queue | Leading and trailing swipe, long-press context menu, More menu, Edit mode, long-press drag reorder, open episode detail (zoom), scroll show notes, back, Suggestions sheet | `video/queue-light.mov` | `video/queue-dark.mov` | `run-light/q-*`, `run-dark/q-*` |
| Mini ↔ full player, scrub, speed, sleep | Tap mini player, play, skip ±, scrub to 60 %, vertical drag on the scrubber, Speed panel (1.5×, back to 1×), Sleep panel (15 min, cancel), Chapters panel, More menu, small drag (cancel), 80 pt flick, long drag (dismiss), reopen, close with chevron | `video/player-light.mov` | `video/player-dark.mov` | `run-light/p-*`, `run-dark/p-*` |
| Library, podcast, episode, settings | Shows grid, Episodes segment and scroll, open Planet Money (zoom), scroll, open an episode, scroll, back ×2, More menu, Settings (4 scroll positions) | `video/library-light.mov` | `video/library-dark.mov` | `run-light/l-*`, `run-dark/l-*` |
| Discover / search | Open Search tab, focus field, type "history", results, open a result, back, a query with no results, clear | `video/discover-light.mov` | `video/discover-dark.mov` | `run-light/d-*`, `run-dark/d-*` |
| Onboarding | Fresh store with `-resetOnboarding`: welcome list, scroll, open a source, back, Skip, empty Queue, empty Library | `video/onboarding-light.mov` | `video/onboarding-dark.mov` | `run/o-*` (light), `run/os-*` (Skip → empty Library), `video/onboarding-skip.mov` |
| Downloads | No Downloads screen exists on `main` (Library has Shows and Episodes only; downloads are a filter in a podcast's episode list and a "Downloaded" smart playlist). Download actions are covered in the Queue swipe and Now Playing More menu captures. | — | — | `run-light/q-02-*`, `run-light/p-09-more.png` |

Frame strips: `sheets/p-open.png` (mini → full player), `sheets/p-dismiss.png` (drag to dismiss),
`sheets/reorder.png` (long-press drag in the queue), `sheets/l-zoom.png` (show tile → podcast), `sheets/d-tab.png`
(Search tab first load).

### What the recordings show at a glance

- **Mini → full player** is a plain full-screen cover sliding up (~0.3 s). Nothing morphs from the mini player;
  the artwork shows a placeholder for one frame, and the title, scrubber and transport shift up by ~16 pt between
  0.3 s and 0.5 s after the cover lands.
- **Drag to dismiss** follows the finger with a rubber band, but a fast 80 pt flick snaps back; only a drag past
  100 pt closes. After closing, the mini player is missing for one frame and reappears.
- **Podcast open** zooms from the tile, but the hero artwork is blank for ~0.2 s and the artwork-color backdrop
  fades in over the next 0.4 s.
- **Long-press on a queue row** opens the context menu; dragging after the lift doesn't reorder (synthetic drag;
  verify on a device). Edit mode reorder works.
- **Search tab** shows skeleton rows, then on two of four launches replaced them with "Couldn't Load Top Shows"
  while the network was up; charts aren't cached between launches.
- **Onboarding Skip** dismisses to an empty Library ("No Shows Yet", Browse Shows, Add Sample Shows); the
  bottom "Choose an Export File" button floats over the last source row without a backing material.
- **Show notes** render as one run-on block: paragraphs and link text from the feed HTML are glued together
  ("…climate changeInside the insurance industry's destruction labEpisode 797…", "InstagramTikTokYouTubeFacebook").


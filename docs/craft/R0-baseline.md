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

## R0.3 System surfaces: Lock Screen, Control Center, CarPlay, Watch

None of these can be exercised from this Mac without hardware or GUI-only simulator controls (`simctl` can't lock
the device, open Control Center or attach the CarPlay window, and no watchOS runtime is installed). What the code
publishes is below, with the exact device steps for Chen. Each "expect" line is what an Apple-quality podcast app
does; anything that differs becomes an R2 finding once seen on the device.

**What the code publishes** (`Packages/JimmyKit/Sources/JimmyKit/Playback/`):

- `NowPlayingController.swift:21-32`: title, show as both artist and album, duration, elapsed time, rate,
  artwork. No chapter number/count, no `MPNowPlayingInfoPropertyMediaType`, no current chapter title.
- `RemoteCommandController.swift:16-75`: play, pause, toggle, skip forward/back with `preferredIntervals` from
  Settings, change playback position. `nextTrackCommand` is explicitly disabled (line 45); no
  `changePlaybackRateCommand`, no bookmark/like command.
- Interruptions and route changes: `AudioSessionLogic.swift` (pure decisions, unit tested) and
  `CurrentPlayViewModel.swift:65-97` (route change observer).
- CarPlay (`Jimmy/CarPlay/CarPlayManager.swift`): `CPTabBarTemplate` with Queue, Library (→ show list) and
  `CPNowPlayingTemplate.shared`. List items carry title and detail text only (no artwork image, no progress); no
  now-playing buttons (rate, chapters).
- Watch (`JimmyWatch/`): vertical pages Now Playing (show, title, progress bar, ±15 and play/pause), Queue (tap to
  play, swipe to remove), Recent; "Open Jimmy on your iPhone" when the phone hasn't been reached yet.

**Needs Chen device: exact steps** (iPhone with Jimmy from `main`, AirPods, a CarPlay head unit or Xcode's CarPlay
simulator window, paired Apple Watch). Record each with the screen recorder; 20 minutes in total.

1. Lock Screen: play an episode with chapters at 1.5×, lock. Expect artwork, episode title, show, elapsed advancing
   at 1.5× rate, chapter title if any, skip buttons showing your Settings intervals. Scrub the Lock Screen bar;
   expect the app's position to match after unlocking.
2. Control Center: open the Now Playing tile, skip back, skip forward, pause. Expect the tile to update within one
   second and the AirPlay route button to show the current route.
3. Dynamic Island (iPhone with one): expect the compact player with artwork and waveform while playing.
4. AirPods: remove one bud (expect pause), put it back (expect resume only if your AirPods setting says so),
   double-tap / press (expect skip forward or play/pause per AirPods settings; next-track is disabled in Jimmy, so a
   "next track" gesture should skip forward rather than do nothing; note what happens).
5. Interruptions: during playback, trigger Siri ("What time is it?"), then a phone call (decline). Expect playback
   to pause and resume on its own after each.
6. Route change: play on Bluetooth speaker/car, disconnect it. Expect pause, no blast from the phone speaker.
7. CarPlay: open Jimmy. Time from tap to a populated Queue list; are there artwork thumbnails; does Now Playing
   show rate and skip buttons; does choosing an episode from Library start it without touching the phone.
8. Watch: open Jimmy on the Watch with the phone app closed, then open. Expect Now Playing to fill within two
   seconds; check whether the skip glyphs match your phone's Skip settings (they're hard-coded to 15) and whether
   the Digital Crown changes volume.

## R0.4 Instruments and timing

All traces and strips under `~/tmp/codex/jimmy-craft/`. Debug build in the simulator: use for *shape* (what happens
in what order, where the main thread goes), not for absolute device numbers.

| Measure | How | Result |
|---|---|---|
| Cold launch, video | `simctl launch` with the screen recording running; strip `sheets/launch-cold.png` (4 fps), video `video/launch-cold.mov` | Tap at 0.75 s → **blank white window until ~2.5 s** → **"Queue Is Empty" with Browse Shows flashes for one frame (~2.75 s)** → queue rows at 3.0 s with three of four artworks still placeholders → mini player at 3.0 s. |
| Cold launch, XCUITest (5 runs) | `driver Flows/Extra.swift LaunchTiming` (`run/launch-timing.txt`) | First queue row 5.6–8.4 s, mini player +1.05 s every run. Includes XCUITest's wait-for-idle and the demo library re-seeding on every `-demoLibrary` launch, so it overstates; the order (rows, then the mini player a second later) is real. |
| App Launch template | `xctrace record --template 'App Launch' --launch` (`traces/launch.trace`) | The simulator records no lifecycle periods (table empty). Time profile: `JimmyApp.init` 390 ms of main-thread work, of which `AppModel.open` (store open) ~305 ms, `AudioSessionController.activate` ~90 ms, `RemoteCommandController.configure` ~40 ms and `AVPlayerItem.init` ~120 ms run on the main thread before the first frame. |
| Animation Hitches | `xctrace --template 'Animation Hitches' --attach Jimmy` during `Perf/testPerfLoop` | **Not supported in the simulator** ("Trace is malformed - run data is missing"). Needs Chen's device; see below. |
| Scroll / player / scrub, Time Profiler | `traces/perf-timeprofile.trace` during `Perf/testPerfLoop` (Library Episodes ×6 fast swipes each way, Planet Money ×6, player open/close ×3, 5 scrubs) | Main-thread app frames are SwiftUI view-list rebuilds of `EpisodeCard` and `EpisodeArtwork`, `LibraryView.viewModePicker` and `LibraryView.body`, plus `EpisodeCard.dateText` (date formatting in the row body). No single hot spot; numbers aren't trustworthy in the simulator. |

**Needs Chen device (10 minutes, Release build from `main` on a ProMotion iPhone):** in Instruments choose
*Animation Hitches*, attach to Jimmy, then: scroll Library → Episodes top to bottom and back fast; open a show with
500+ episodes and fling to the end; open and close Now Playing three times (tap, then drag); scrub back and forth for
5 s. Save as `jimmy-hitches.trace`. Then *App Launch* with Jimmy killed: record a cold launch to the queue. Targets
from the rubric: zero hitches > 1 frame in those flows; first frame with real content ≤ 400 ms.

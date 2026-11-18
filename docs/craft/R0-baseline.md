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

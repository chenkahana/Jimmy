# Agent guide for Jimmy

Instructions for AI coding agents (and a fast orientation for humans). The [README](README.md),
[CONTRIBUTING.md](CONTRIBUTING.md) and [docs/architecture.md](docs/architecture.md) are the source of truth; this
file only adds what an agent needs to work safely.

## What Jimmy is

A queue-centric podcast player for iPhone (iOS 27+), with an Apple Watch app and CarPlay. One SwiftUI app over the
**JimmyKit** Swift package. Swift 6 language mode, main-actor default isolation. One dependency: GRDB.

## Build and verify

```bash
make bootstrap   # once: toolchain check, XcodeGen, project generation
make kit         # JimmyKit package tests
make build       # unsigned simulator build (what CI runs)
make test        # app unit tests on $(SIM), default "iPhone 17 Pro"
```

- `project.yml` is the source of truth. `Jimmy.xcodeproj` is generated and git-ignored; never hand-edit it.
- `make run` builds, installs, launches and screenshots the app in the simulator (`scripts/run_in_simulator.sh`).
- `make screenshots` launches with `-demoLibrary` (see `Jimmy/App/DemoLibrary.swift`) and recaptures
  `docs/screenshots/`.
- Deep links for checking screens: `jimmy://queue`, `jimmy://library`, `jimmy://discover`, `jimmy://settings`.

## Where things go

- `Packages/JimmyKit`: models, `Store` (GRDB, migrations), feeds, `Playback`, `Downloads`, importers, watch
  session types. Anything the app, CarPlay or the watch share belongs here, with tests.
- `Jimmy/App`: `AppModel`, the one `@Observable` app model, split into `AppModel+<Area>.swift` extensions.
- `Jimmy/Views`, `Jimmy/Onboarding`, `Jimmy/Suggestions`, `Jimmy/Assistant`, `Jimmy/CarPlay`: UI and features.
  Views read from and call into `AppModel`; no business logic in views.
- `Jimmy/Services`: older app-side services still being moved into JimmyKit. Don't add new ones here.
- `Tests/Fixtures/Feeds`: real-world feed shapes. Add a fixture when you fix a parsing bug.

## Rules that matter

- **The user's library survives.** Schema changes add a new migration; never edit a shipped one.
- **Off the main actor.** Database, network and file work goes through JimmyKit's async API.
- **Privacy.** No analytics, tracking or SDKs that collect data. AI features use Apple's on-device model only.
  Anything new that leaves the device must be added to [docs/privacy.md](docs/privacy.md).
- **Replace, don't layer.** When moving a feature onto JimmyKit, delete the code it replaces in the same PR.
- Keep changes small and focused; update [CHANGELOG.md](CHANGELOG.md) under "Unreleased" for user-visible changes.

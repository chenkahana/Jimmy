# Instruments Workflow

This guide defines the repeatable performance workflow for Jimmy's v7.2 shell.

## What To Measure

Jimmy now emits signposts for the highest-value interaction paths:

- `Shell First Render`
- `Tab Switch`
- `Discover Search`
- `Queue Reorder`
- `Podcast Detail Open`

These are emitted from [`PerformanceDiagnostics.swift`](/Users/chenk/Jimmy/Jimmy/Utilities/PerformanceDiagnostics.swift) and surfaced locally through the debug overlay when `JIMMY_SHOW_PERF_HUD=1`.

## Target Budgets

- Warm launch to first interactive shell: under `500ms`
- Perceived tab switch response: under `100ms`
- Discover search update latency: no visible hitching during incremental result updates
- Queue reorder persistence: responsive drag feedback with no main-thread stall
- Detail open: fast enough to preserve transition continuity without a visible pause

## Local Verification

Build and run with the exact repo commands first:

```bash
xcodebuild -project Jimmy.xcodeproj -scheme Jimmy -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build
./scripts/run_in_simulator.sh --skip-build
```

Optional debug HUD:

```bash
JIMMY_SHOW_PERF_HUD=1 ./scripts/run_in_simulator.sh --skip-build
```

## Instruments Pass

Use these Instruments templates for the live shell:

1. `Hangs`
2. `Time Profiler`
3. `SwiftUI`
4. `Concurrency`

For each run, exercise the same core path:

1. Cold launch into Queue
2. Switch Queue -> Library -> Discover -> Settings
3. Run one Discover search and cancel it
4. Open one featured podcast detail
5. Reorder one queue item

## Failure Thresholds

Investigate immediately if you see any of the following:

- `Shell First Render` consistently over `500ms`
- `Tab Switch` consistently over `100ms`
- Main-thread parsing or database work during launch or tab switching
- Search-result updates causing visible scroll hitching
- Transition animations pausing before detail content appears

## Notes

- Run the simulator checks before profiling so you know you are measuring the current live path.
- Prefer fixing live-surface bottlenecks before broader repo cleanup.
- If a regression is user-visible but not obvious in the HUD, capture it with `Hangs` first and then confirm with `Time Profiler`.

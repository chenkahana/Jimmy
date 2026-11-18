RESUME HERE: PRs #42 (J-22), #43 (J-06), #44 (J-23) open in CI, merge each when green (CHANGELOG conflicts: merge main into the branch); next J-26.

# Implementation tracker

Chen approved implementation 2026-11-18 for backlog items that don't need his decision. One PR per slice of
`R5-backlog.md` R5.3, branch `craft/<id>-<slug>`, worktree `~/.worktrees/Jimmy/<branch-tail>`, squash-merged when CI
is green. Simulator checks on a dedicated iPhone Duo (iOS 27.1) "Jimmy Impl", driver and captures under
`~/tmp/codex/jimmy-impl/`.

## Top items (lead's order)

- [x] J-01 Mini player Play/Skip 44 pt targets — PR https://github.com/chenkahana/Jimmy/pull/41
- [ ] J-22 Now Playing chevron, •••, Speed/Sleep/Chapters targets — PR https://github.com/chenkahana/Jimmy/pull/42 (CI)
- [ ] J-30 No nameless "More" duplicate — skipped after 2 attempts (icon-only `Label`, `.accessibilityElement(children: .combine)`): the element is SwiftUI `Menu`'s own button and the simulator tree can't show VoiceOver focus. Needs a VoiceOver check on a device.
- [ ] J-06 Queue row Play 44 pt — PR https://github.com/chenkahana/Jimmy/pull/43 (CI)
- [ ] J-11 One VoiceOver stop per queue row — skipped after 2 attempts (`.accessibilityHidden(true)` on the Play button, `.accessibilityElement(children: .ignore)` on the row): neither changed the simulator's tree. Needs a VoiceOver check on a device.
- [ ] J-23 Player drag follows the finger; flick dismisses with velocity — PR https://github.com/chenkahana/Jimmy/pull/44 (CI)
- [ ] J-26 Haptics and symbol bounce on skip, speed, sleep
- [ ] J-02 No blank window or "Queue Is Empty" flash at launch
- [ ] J-13 One name for Mark Played
- [ ] J-17 Show notes keep paragraphs and links
- [ ] J-16 Cache Top Shows on device; no error page when a cache exists

## Remaining non-gated

- [ ] J-28 + J-29 Hide Chapters with none; fill the ••• menu
- [ ] J-20 + J-21 One duration and one date format
- [ ] J-14 + J-32 Naming pass (Follow, Send Feedback, "…")
- [ ] J-18 Podcast hero art and color on the first frame
- [ ] J-25 Speed dial
- [ ] J-09 Undo for queue Remove; confirm Clear All
- [ ] J-40 + J-05 Text styles for badges and banner; mini player at AX sizes
- [ ] J-41 + J-42 VoiceOver announcements; shimmer honors Reduce Motion
- [ ] J-10 Suggestions placeholder rows and Done
- [ ] J-31 + J-34 + J-04 Sleep panel, onboarding button, tip placement
- [ ] J-27 Scrubber growth and chapter ticks
- [ ] J-24 + J-03 Mini player ↔ Now Playing morph
- [ ] J-36 Restore tab and place after relaunch
- [ ] J-33 + J-15 Feedback form closes on completion; Library first-load placeholders
- [ ] J-19 Pinned header stacking (needs an iPhone check)
- [ ] J-08 Long-press reorder (needs a device check)
- [ ] J-38 CarPlay artwork and rate button (needs CarPlay)
- [ ] J-39 Watch glyphs, buttons, artwork (needs a Watch)

## Waiting: Chen

- [ ] J-07 Swipe action tints (waiting: Chen, `design.md` one-accent rule)
- [ ] J-12 Downloads view (waiting: Chen, scope)
- [ ] J-37 Lock Screen chapters, rate, "next track" (waiting: Chen, what "next" means)
- [ ] J-35 App Intents, widgets, controls (waiting: Chen, which system feature first)

## Device checks owed

- J-30, J-11: VoiceOver on an iPhone (Now Playing "More"; a queue row).
- J-23: drag and flick feel on a ProMotion iPhone.

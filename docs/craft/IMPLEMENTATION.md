RESUME HERE: J-01 PR #41 open, waiting for CI; next J-22 + J-30.

# Implementation tracker

Chen approved implementation 2026-11-18 for backlog items that don't need his decision. One PR per slice of
`R5-backlog.md` R5.3, branch `craft/<id>-<slug>`, worktree `~/.worktrees/Jimmy/<branch-tail>`, squash-merged when CI
is green. Simulator checks on a dedicated iPhone Duo (iOS 27.1) "Jimmy Impl", driver and captures under
`~/tmp/codex/jimmy-impl/`.

## Top items (lead's order)

- [ ] J-01 Mini player Play/Skip 44 pt targets — PR https://github.com/chenkahana/Jimmy/pull/41 (CI)
- [ ] J-22 + J-30 Now Playing chevron, •••, Speed/Sleep/Chapters targets; no nameless "More" duplicate
- [ ] J-06 + J-11 Queue row Play 44 pt; one VoiceOver stop per row
- [ ] J-23 Player drag follows the finger; flick dismisses with velocity
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

- None yet.

RESUME HERE: #41–#52 merged (CI green each; CHANGELOG-only merges admin-landed). Remaining non-gated items go into ONE batch PR, branch craft/batch-1 (worktree ~/.worktrees/Jimmy/craft-batch-1), one commit per item, CI once. Next: J-28/J-29, J-05, then the rest below.

# Implementation tracker

Chen approved implementation 2026-11-18 for backlog items that don't need his decision. One PR per slice of
`R5-backlog.md` R5.3, branch `craft/<id>-<slug>`, worktree `~/.worktrees/Jimmy/<branch-tail>`, squash-merged when CI
is green. Simulator checks on a dedicated iPhone Duo (iOS 27.1) "Jimmy Impl", driver and captures under
`~/tmp/codex/jimmy-impl/`.

## Top items (lead's order)

- [x] J-01 Mini player Play/Skip 44 pt targets — PR https://github.com/chenkahana/Jimmy/pull/41
- [x] J-22 Now Playing chevron, •••, Speed/Sleep/Chapters targets — PR https://github.com/chenkahana/Jimmy/pull/42
- [ ] J-30 No nameless "More" duplicate — skipped after 2 attempts (icon-only `Label`, `.accessibilityElement(children: .combine)`): the element is SwiftUI `Menu`'s own button and the simulator tree can't show VoiceOver focus. Needs a VoiceOver check on a device.
- [x] J-06 Queue row Play 44 pt — PR https://github.com/chenkahana/Jimmy/pull/43
- [ ] J-11 One VoiceOver stop per queue row — skipped after 2 attempts (`.accessibilityHidden(true)` on the Play button, `.accessibilityElement(children: .ignore)` on the row): neither changed the simulator's tree. Needs a VoiceOver check on a device.
- [x] J-23 Player drag follows the finger; flick dismisses with velocity — PR https://github.com/chenkahana/Jimmy/pull/44
- [x] J-26 Haptics and symbol bounce on skip, speed, sleep — PR https://github.com/chenkahana/Jimmy/pull/45
- [x] J-02 No "Queue Is Empty" flash at launch — PR https://github.com/chenkahana/Jimmy/pull/46 (blank pre-first-frame window not changed: needs a Release App Launch trace on an iPhone)
- [x] J-13 One name for Mark Played — PR https://github.com/chenkahana/Jimmy/pull/47
- [x] J-17 Show notes keep paragraphs and links — PR https://github.com/chenkahana/Jimmy/pull/48
- [x] J-16 Cache Top Shows on device; no error page when a cache exists — PR https://github.com/chenkahana/Jimmy/pull/49

## Remaining non-gated

- [ ] J-28 + J-29 Hide Chapters with none; fill the ••• menu (Go to Episode, Go to Show) — batch PR (craft/batch-1)
- [x] J-20 + J-21 One duration and one date format — PR https://github.com/chenkahana/Jimmy/pull/50
- [x] J-14 (naming) + J-32 Naming pass (Follow, Send Feedback, "…") — PR https://github.com/chenkahana/Jimmy/pull/51
- [x] J-18 Podcast hero art on the first frame — PR https://github.com/chenkahana/Jimmy/pull/52
- [ ] J-25 Speed dial
- [ ] J-09 Undo for queue Remove; confirm Clear All
- [ ] J-40 Fixed font sizes — skipped: the 10 pt badges and 12–16 pt banner are in dead code (`StatusBadge` only via unused `EpisodeRowView`, `ErrorBannerView` only via unused `PodcastSearchViewModel`); live fixed sizes are capped glyphs
- [ ] J-05 Mini player at AX sizes — batch PR (craft/batch-1)
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

- J-30, J-11: needs device VoiceOver (Now Playing "More"; a queue row).
- J-26: haptics on an iPhone.
- J-02: Release App Launch trace on an iPhone (blank window before the first frame).
- J-23: drag and flick feel on a ProMotion iPhone.

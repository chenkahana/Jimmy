RESUME HERE: R0.5 finish R0-baseline.md (summary, driver source appendix)

# Progress log

Append-only. One line per completed step: date, step, what was done, commit.

| Date | Step | Done | Commit |
|---|---|---|---|
| 2026-11-18 | Setup | Repo resolved to `chenkahana/Jimmy` `main` `601bfa4` (local `~/Jimmy` is the stale `Jimmy-archive` checkout). Worktree, PLAN.md, PROGRESS.md, starting evidence re-run on `main`. | see git log |
| 2026-11-18 | R0.1 | Built main for iOS 27.1 sim (iPhone Duo 'Jimmy Craft'), launched with -demoLibrary, XCUITest driver outside repo, first tab dump | 459be36 |
| 2026-11-18 | R0.2 | Recorded queue, player, library/podcast/episode/settings, discover, onboarding flows in Light and Dark (videos in ~/tmp/codex/jimmy-craft/video); no Downloads screen exists | 6068dbe |
| 2026-11-18 | R0.3 | Lock Screen/Control Center/CarPlay/Watch: not reachable from sim; documented what code publishes + exact device steps for Chen | 6d0307d |
| 2026-11-18 | R0.4 | Cold launch video (blank ~1.75 s, empty-queue flash), XCUITest launch timing x5, App Launch + Time Profiler traces; Animation Hitches unsupported in sim -> device steps | edda38c |

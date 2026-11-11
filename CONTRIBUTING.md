# Contributing to Jimmy

Thanks for helping make Jimmy better. This guide covers how to report problems, propose changes and get a pull
request merged.

## Before you start

- **Bugs and ideas** go in [GitHub Issues](https://github.com/chenkahana/Jimmy/issues/new/choose). Search first; add
  to an existing issue rather than opening a duplicate.
- **Security issues** must not be filed publicly. Follow [SECURITY.md](SECURITY.md).
- **Larger changes** (new features, new dependencies, schema or playback changes) need an issue agreed with a maintainer
  before you write the code.

By opening a pull request you confirm that you wrote the change, or have the right to submit it, and you agree
that it is licensed under the [Mozilla Public License 2.0](LICENSE), the same license as the rest of Jimmy.

## Development setup

```bash
make bootstrap
```

Then open `Jimmy.xcodeproj`. Requirements, schemes and common commands are in the
[README](README.md). The Xcode project is built from `project.yml` via XcodeGen: edit
`project.yml`, never the generated project, and run `make project` afterwards.

## Branches and commits

- `main` is always releasable. Work on a branch named `<type>/<short-description>`, e.g. `fix/playback-resume-time`.
- Write commit subjects in the imperative mood, under 72 characters ("Fix duplicate subscriptions after import").
  Explain *why* in the body when it isn't obvious.
- Keep a pull request to one concern. Refactors go in their own pull request.
- Add follow-up commits to an open pull request instead of force-pushing; it is squashed when merged.

## Code guidelines

- **Swift 6, strict concurrency.** Views and ViewModels default to `@MainActor`. Keep database, feed fetching and
  playback work off the main actor; the UI must never wait on SQLite or the network.
- **Shared logic lives in JimmyKit.** Anything the app and CarPlay/Watch need (models, persistence, feed fetching,
  playback) belongs in `Packages/JimmyKit`, not in the app target.
- **SwiftUI first.** Use UIKit only where SwiftUI has no equivalent (CarPlay controllers), and keep it minimal.
- **Schema changes** need a new migration in `JimmyKit`; never edit a shipped migration.
- **Privacy.** Don't add analytics, tracking or third-party SDKs that collect data. Anything new that leaves the
  device must be reflected in [docs/privacy.md](docs/privacy.md).
- **Accessibility.** Every control needs a VoiceOver label, works with Dynamic Type and respects Reduce Motion.
- **Comments** explain intent and constraints, not what the next line does.

## Checks before you open a pull request

```bash
make build
```

- Run the app: an iPhone 17 Pro simulator on iOS 27.
- If you changed playback, verify it resumes correctly.
- If you changed the database schema, test a migration from the previous version.
- Fill in the pull request template, including screenshots or a recording for UI changes.

CI builds the project on every pull request; it must pass before review.

## Code of conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

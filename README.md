# Jimmy

**A queue-centric podcast player for iPhone.**

One queue drives everything: save an episode from anywhere, and it's the next thing that plays. Subscriptions,
playback progress, downloads and listening stats all live on your device — nothing is uploaded anywhere.

[![CI](https://github.com/chenkahana/Jimmy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/chenkahana/Jimmy/actions/workflows/ci.yml)
![iOS 27+](https://img.shields.io/badge/iOS-27%2B-000000?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License](https://img.shields.io/badge/license-MPL--2.0-brightgreen)](LICENSE)

[Features](#features) · [Screenshots](#screenshots) · [Architecture](#architecture) · [Getting started](#getting-started) · [Privacy](#privacy) · [Contributing](#contributing)

## Features

| | |
|---|---|
| **One queue** | Save an episode from a podcast's page, Discover or search, and it joins the queue in play order. Reorder, promote a must-hear episode to the top, or clear the whole thing. |
| **Player** | Resume position, skip silence and volume boost, variable speed, a sleep timer (duration or end-of-episode), and chapter navigation for feeds that publish chapters. |
| **Library** | Your subscriptions with artwork, unread counts and per-show auto-queue and notification settings. |
| **Smart playlists, transcripts, bookmarks** | Rule-based playlists, episode transcripts where the feed provides them, timestamped bookmarks, and running listening stats. |
| **Downloads** | Episodes download in the background and play from disk, so a queue survives a bad connection. |
| **Import** | Bring your subscriptions in from an OPML file, an Apple Podcasts export, a Spotify list or a Google Takeout archive. |
| **Apple Watch** | A companion watch app shows Now Playing, Queue and Recent, and controls the phone's player. |
| **CarPlay** | Browse the queue and library and control playback from the car. |
| **iCloud sync (optional)** | Turn it on in Settings to carry subscriptions, queue order and playback progress to your other devices through your own private iCloud account. |
| **Private by design** | No accounts, no analytics, no crash-reporting SDK. Feeds are fetched directly from each show's host — see [Privacy](#privacy). |

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/queue-light.png" alt="The Queue screen" width="200"><br><sub>Queue</sub></td>
    <td align="center"><img src="docs/screenshots/nowplaying-light.png" alt="The Now Playing screen" width="200"><br><sub>Now Playing</sub></td>
    <td align="center"><img src="docs/screenshots/library-light.png" alt="The Library screen" width="200"><br><sub>Library</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/podcast-light.png" alt="A podcast's detail screen" width="200"><br><sub>Podcast</sub></td>
    <td align="center"><img src="docs/screenshots/discover-light.png" alt="The Discover screen" width="200"><br><sub>Discover</sub></td>
    <td align="center"><img src="docs/screenshots/settings-light.png" alt="The Settings screen" width="200"><br><sub>Settings</sub></td>
  </tr>
</table>

Dark mode is fully supported; these are the light-mode shots. Captured from a demo library of public podcasts —
see `Tools/screenshots.sh` and `Jimmy/App/DemoLibrary.swift`.

## Architecture

Jimmy is one SwiftUI app over a core Swift package, **JimmyKit** (models, a GRDB store, feed parsing and
fetching, and `Playback`). The app is mid-migration onto that core, moving one screen at a time — see
[PLAN.md](PLAN.md) for the plan and [docs/architecture.md](docs/architecture.md) for the full picture, including
what still runs on the pre-JimmyKit services.

| Path | What it holds |
|---|---|
| [`Jimmy/`](Jimmy) | The iPhone app: views, view models, and the screens already moved onto `AppModel`/JimmyKit |
| [`Packages/JimmyKit`](Packages/JimmyKit) | Core package: models, the GRDB store and migrations, feed parsing/fetching, `Playback`, downloads, import parsers |
| [`JimmyWatch/`](JimmyWatch) | The watch app |
| [`Tests/`](Tests), [`Packages/JimmyKit/Tests`](Packages/JimmyKit/Tests) | Unit tests for the app and for JimmyKit |

The Xcode project is generated from [`project.yml`](project.yml) via XcodeGen; edit the YAML file, never the
generated project.

## Getting started

### Requirements

- macOS with Xcode 27 (iOS 27 SDK) and the iPhone 17 Pro (or another iOS 27) simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Build and run

```bash
git clone https://github.com/chenkahana/Jimmy.git
cd Jimmy && make bootstrap
make run
```

### Common tasks

| Command | What it does |
|---|---|
| `make bootstrap` | Checks the toolchain, installs XcodeGen if missing, generates the project |
| `make build` | Builds the app for the simulator (unsigned) — what CI runs |
| `make test` | Runs the unit tests (override the simulator with `SIM="..."`) |
| `make kit` | Runs the JimmyKit package tests on their own |
| `make run` | Builds, installs, launches and screenshots Jimmy in the simulator |
| `make screenshots` | Seeds the `-demoLibrary` demo data and recaptures `docs/screenshots/` |
| `make archive` | Signed Release archive for App Store Connect |

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full development setup.

## Privacy

Jimmy collects no data. Your library stays on your device, iCloud sync (when you turn it on) goes through your own
private iCloud account, and there are no accounts, analytics or crash-reporting SDKs. The full policy is in
[docs/privacy.md](docs/privacy.md).

## Coming next

Jimmy is partway through [a simplification plan](PLAN.md). Still ahead:

- Moving Podcast detail/Episode, Discover/Search, Settings/Import and CarPlay onto JimmyKit (each PR deletes the
  old code it replaces).
- Standalone playback and downloads on the Apple Watch app.
- On-device AI (Apple's on-device model only): a chat that can act on requests ("play the latest Daily", "set a
  20-minute sleep timer"), and on-device suggestions for what to listen to next.
- A full hands-on QA pass and a release guide ahead of the first tagged version.

## Contributing

Bug reports and feature requests are welcome through
[GitHub Issues](https://github.com/chenkahana/Jimmy/issues/new/choose). Read [CONTRIBUTING.md](CONTRIBUTING.md)
before opening a pull request, and report security issues as described in [SECURITY.md](SECURITY.md), not in public
issues.

## License

Jimmy is licensed under the [Mozilla Public License 2.0](LICENSE). Third-party components and their licenses are
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

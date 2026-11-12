# Changelog

All notable changes to Jimmy are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Download buttons on Now Playing, episode detail, and episode rows now download the episode.

### Removed

- Firebase analytics and crash reporting SDK.
- Four legacy CI workflows and their supporting scripts; replaced with one minimal workflow.

### Changed

- A calmer look: system backgrounds instead of the gradient backdrop, no card shadows, plain section headers,
  standard empty states, and a new accent color.
- Settings is a native grouped form: Playback, Appearance, Sync & Backup, Import & Export, About, with
  destructive actions last and the app version shown once.
- Simplified architecture with a new core package, JimmyKit.
- Xcode project now generated from `project.yml` via XcodeGen; build with `make build`.

### Added

- Single CI workflow for build validation.
- Community files: LICENSE, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md, SUPPORT.md, THIRD_PARTY_NOTICES.md, documentation.
- A real Apple Watch app (Now Playing, Queue, Recent) that controls the phone's player over
  WatchConnectivity. Standalone playback with downloads to the watch is planned for later.
- Release guide in `docs/releases/README.md`.

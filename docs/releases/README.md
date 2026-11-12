# Release guide

How to ship a new version of Jimmy to the App Store.

## 1. Before a release

- Run the checklist in [`docs/qa.md`](../qa.md) on a real device and record the round in its log. No P1 or P2 issue may be open.
- Run these locally, all green:

  ```bash
  make build
  make test SIM="<an iOS 27 simulator>"
  make kit
  ```

- CI (`.github/workflows/ci.yml`) must be green on `main`.

## 2. Bump the version

1. In `project.yml`, set `MARKETING_VERSION` to the new version (for example `8.0`). Raise `CURRENT_PROJECT_VERSION` as well: App Store Connect rejects an upload whose build number it has already seen. XcodeGen regenerates the project on the next `make build`.
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [8.0] - YYYY-MM-DD`, and add a fresh, empty `## [Unreleased]` above it.
3. Open a pull request with both changes. `main` is protected: changes land only through a PR, squash-merged, with the `build` check green.

## 3. Archive and upload

1. Build the signed archive:

   ```bash
   make archive
   ```

   It lands at `build/archives/Jimmy.xcarchive`.
2. Upload it by hand: Xcode → Window → Organizer → select the archive → Distribute App → App Store Connect.
3. In App Store Connect, add the build to an internal TestFlight group and check on a real device:
   - The library opens with your subscriptions intact.
   - An episode plays, pauses and resumes where it stopped.
   - CarPlay shows the queue and plays.
   - The Watch app shows Now Playing and controls the phone.
4. Submit the build for review in App Store Connect. This is manual.

## 4. Tag and publish the release

After the version PR merges, tag its squash commit on `main`:

```bash
git tag -a v8.0 -m "Jimmy 8.0" <merge-commit>
git push origin v8.0
```

Then create the GitHub release from that version's `CHANGELOG.md` section:

```bash
gh release create v8.0 --title "Jimmy 8.0" --notes-file <file with the changelog section>
```

## 5. Screenshots

When the UI changed, refresh the README screenshots:

```bash
make screenshots
```

It seeds the `-demoLibrary` demo data on an iOS 27 simulator. It captures Queue, Library, Discover, Settings, a podcast page and Now Playing, in light and dark, into `docs/screenshots/`. Commit the results with the release PR.

## History

Older release notes stay here for reference: [v1](v1.md), [v2](v2.md), [v2 release notes](RELEASE_NOTES_v2.md).

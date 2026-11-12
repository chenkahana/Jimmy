# Release Guide

This guide covers the process for releasing a new version of Jimmy to the App Store.

## Before a Release

1. **Complete the QA checklist.** Open `docs/qa.md` and run through the full checklist on a real device and a simulator. Record the results in the QA Rounds Log table. Zero P1 and P2 issues are required before release.

2. **Verify local builds and tests pass.**
   ```bash
   make build
   make test SIM="iPhone 17 Pro"
   make kit
   ```

3. **Verify CI is green on `main`.** All pull requests must merge through `main` with a passing `build` check.

## Bump the Version

1. **Edit `project.yml`.** Update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to the new version number (e.g., from `7.2` to `7.3`). XcodeGen will regenerate the project with the new version.

2. **Update `CHANGELOG.md`.** Move the `[Unreleased]` section into a new `[X.Y] - YYYY-MM-DD` section with today's date. For example:
   ```markdown
   ## [7.3] - 2024-11-12

   ### Added
   - Feature one.
   - Feature two.

   ### Changed
   - Change one.

   ### Removed
   - Removed item.

   ## [Unreleased]

   (nothing yet)
   ```

3. **Add a release guide note** (if not already present). Under `## [Unreleased]` in `CHANGELOG.md`, add:
   ```markdown
   ### Added
   - Release guide in `docs/releases/README.md`.
   ```

4. **Open a pull request.** Commit the version bump and changelog changes. The PR must pass the `build` check; main is protected and requires PR merge with squash-merge.

5. **Merge the PR.** Once the build passes and you approve, merge with squash-merge (GitHub's default on main).

## Archive and Upload

1. **Create the release archive.**
   ```bash
   make archive
   ```
   This creates a signed release archive at `build/archives/Jimmy.xcarchive`.

2. **Upload to App Store Connect.** Open Xcode's Organizer:
   - Menu: Window → Organizer
   - Select Jimmy
   - Click the archive you just created
   - Click "Distribute App"
   - Follow the wizard to upload to App Store Connect

3. **TestFlight check.** Once uploaded, create an external TestFlight build in App Store Connect. Test on at least one real device to verify:
   - Library opens and displays subscribed podcasts
   - Playback works (tap an episode, play audio)
   - CarPlay works (if available)
   - Apple Watch app works (if available)

## Tag

1. **After the release PR merges,** note the merge commit hash.

2. **Create the git tag.**
   ```bash
   git tag -a vX.Y -m "Jimmy X.Y" <merge-commit-hash>
   git push origin vX.Y
   ```

3. **Create the GitHub release.** Extract the release notes from the CHANGELOG section and create a GitHub release:
   ```bash
   gh release create vX.Y --notes "Your release notes here"
   ```
   Or use the GitHub web interface.

## Screenshots

If the UI changed significantly, update the screenshot gallery:
```bash
make screenshots
```

This seeds the app with demo data, launches on an available iOS 27 simulator, and captures light and dark mode screenshots of all main screens (Queue, Library, Discover, Settings, Podcast Detail, Now Playing) into `docs/screenshots/`.

Screenshots are committed to the repository for documentation.

## Release History

This folder also contains older release notes:

- [v1.md](./v1.md) — Jimmy Version 1
- [v2.md](./v2.md) — Jimmy Version 2
- [RELEASE_NOTES_v2.md](./RELEASE_NOTES_v2.md) — Version 2 release notes

These are preserved for historical reference.

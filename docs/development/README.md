# Development Documentation

This section contains technical documentation for developers working on Jimmy.

## Files

### [Build Status & Troubleshooting](./BUILD_STATUS.md) 🔧
Comprehensive build status, troubleshooting guide, and build fixes applied to the project.

### [Jimmy Module README](./JIMMY_MODULE_README.md) 📋
Technical documentation for the Jimmy module, including architecture, features, and implementation details.

### SwiftLint
The project uses [SwiftLint](https://github.com/realm/SwiftLint) for code style checks. Install it with Homebrew:

```bash
brew install swiftlint
```

On Linux, download a prebuilt binary from the SwiftLint releases page and place it in your `PATH`. The `scripts/run_swiftlint.sh` script skips linting if SwiftLint is missing.

---

*These documents help developers understand the technical aspects of building and maintaining Jimmy.* 
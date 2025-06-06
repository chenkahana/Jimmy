# Jimmy

A minimalist, queue-centric iOS podcast app inspired by Google Podcasts with enhanced search and subscription capabilities, featuring a lock-screen widget for seamless playback control.

## 🚨 Current Project Status (Updated June 2025)

### ✅ Main App - **FULLY FUNCTIONAL**
- ✅ **Builds successfully** with no errors
- ✅ **All core features** implemented and working
- ✅ **Audio playback** with comprehensive controls
- ✅ **Queue management** and episode tracking
- ✅ **Import functionality** (OPML, Apple Podcasts, Google Takeout)
- ✅ **Modern SwiftUI interface** with dark mode support
- ✅ **Offline fallback** with cached episodes when network is unavailable
- ✅ **Crash and error logging** with exportable log file

### ✅ Lock-Screen Widget - **FULLY INTEGRATED**
- ✅ **Widget code fully implemented** and tested
- ✅ **Data synchronization** between app and widget via App Groups
- ✅ **Widget extension target configured** in Xcode
- 📋 **Detailed setup guide** available in `Jimmy/WIDGET_README.md`

### ⚠️ Apple Watch App - **IN PROGRESS**
- 🆕 **Basic watch app code** in `WatchFiles/` directory
- ⚠️ **Requires Xcode Watch App target setup**
- 💫 **Watch connectivity implemented** for playback control
- 📋 **Instructions** in `Jimmy/WATCH_README.md`

## Overview
Jimmy is a personal podcast app for iPhone, designed for simplicity, speed, and a queue-focused listening experience. It allows you to import your podcast subscriptions, discover and manage shows, and listen to episodes with a clean, modern interface. The app includes a beautiful lock-screen widget that matches your wireframe design for seamless playback control.

## 🎯 Features

### Core Functionality
- **Queue-centric design**: Primary focus on managing your listening queue
- **Subscription management**: Import from various sources (OPML, Apple Podcasts)  
- **Episode downloads**: Download episodes for offline listening
- **Progress tracking**: Resume playback where you left off
- **Modern UI**: Clean interface with dark mode support
- **🆕 Lock-screen widget**: Control playback directly from lock screen

### 🔒 Lock-Screen Widget Features
- **Episode artwork**: 40x40 point album art display
- **Episode title**: Truncated title display
- **Progress timeline**: Visual playback progress bar  
- **Interactive controls**:
  - Seek backward 15 seconds
  - Play/Pause toggle
  - Seek forward 15 seconds

### Import Options
- **OPML files**: Import subscriptions from exported files
- **Apple Podcasts**: Import directly from your Apple Podcasts library
- **Google Podcasts**: Import from Google Takeout exports
- **Apple JSON**: Import bulk subscriptions using the provided web extractor
- **Spotify**: Import from exported Spotify show links

### Playback Features  
- **Variable speed**: Adjustable playback speed (0.75x to 2x)
- **Background play**: Continues playing in background
- **Audio controls**: Standard media controls and lock screen integration
- **CarPlay support**: Browse your queue and control playback in the car
- **Widget integration**: Data sync between main app and widget
- **Watch app companion**: Control playback from Apple Watch

### User Experience
- **Search functionality**: Find podcasts and episodes quickly
- **Customizable swipe actions**: Configure swipe behaviors
- **Notifications**: Get notified of new episodes
- **iCloud sync**: Keep data synced across devices

## 🚀 Getting Started

### Main App Setup
1. Clone the repository: `git clone git@github.com:chenkahana/Jimmy.git`
2. Open `Jimmy.xcodeproj` in Xcode
3. Build and run the project on your iOS device or simulator
4. Import your podcast subscriptions using one of the available methods
5. Start adding episodes to your queue and enjoy listening!

### Widget Setup (Optional)
The lock-screen widget ships as a separate extension. To rebuild or modify:

1. **See detailed instructions** in `Jimmy/WIDGET_README.md`
2. **Ensure App Groups** `group.com.chenkahana.jimmy` are enabled
3. **Build and test** on a physical device

## 📋 Build Information

### Recent Fixes Applied:
- ✅ **Resolved multiple @main attributes conflict**
- ✅ **Fixed widget TimelineProvider implementation**
- ✅ **Separated widget files from main app target**
- ✅ **Prepared App Groups configuration**
- 🆕 **Added file corruption recovery and low disk space handling**
- 🆕 **Fixed memory leaks identified with Instruments**

### Build Status:
- **Main App**: ✅ Builds successfully
- **Widget Extension**: ✅ Builds successfully
- **Dependencies**: ✅ All resolved
- **Code Signing**: ✅ Configured

## 🛠 Requirements
- iOS 18.4+
- Xcode 16.0+
- Swift 5.9+
- Physical device (for widget testing)

## 🧪 Running Tests
Run all available tests. On macOS the script uses `xcodebuild`, otherwise it
falls back to Swift Package Manager:

```bash
./scripts/run_all_tests.sh
```

## 📂 Project Structure

```
Jimmy/
├── Jimmy/                    # Main app target
│   ├── Models/              # Data models (Podcast, Episode, etc.)
│   ├── Views/               # SwiftUI views (QueueView, PodcastListView, etc.)
│   ├── ViewModels/          # ObservableObject classes for state management
│   ├── Services/            # Logic for syncing, importing, backup, audio playback
│   │   └── WidgetDataService.swift  # Widget data sharing
│   └── Utilities/           # Helpers (accessibility, parsers, etc.)
├── JimmyWidgetExtension/    # Widget extension target
│   ├── JimmyWidgetBundle.swift
│   ├── JimmyWidgetExtension.swift
│   ├── WidgetIntents.swift
│   ├── Info.plist
│   └── JimmyWidgetExtension.entitlements
├── WatchFiles/              # Apple Watch app implementation files
│   ├── JimmyWatchApp.swift
│   ├── WatchContentView.swift
│   └── WatchPlayerManager.swift
└── Documentation/
    ├── WIDGET_README.md     # Comprehensive widget setup guide
    ├── FEATURE_SUMMARY.md   # Feature documentation
    └── Other docs
```

## 📚 Documentation

### Essential Reading:
- **Widget Setup**: `Jimmy/WIDGET_README.md` - Complete widget implementation guide
- **Watch Setup**: `Jimmy/WATCH_README.md` - Apple Watch companion instructions
- **Features**: `Jimmy/FEATURE_SUMMARY.md` - Detailed feature documentation
- **App Summary**: `APP_RENAME_SUMMARY.md` - Project overview

### Quick Links:
- **Widget Status**: Implementation complete, Xcode setup required
- **Watch Status**: Connectivity implemented, Xcode setup required
- **Build Issues**: All resolved, main app builds successfully
- **Repository**: Published and updated on GitHub

## 🔧 Troubleshooting

If you encounter issues:

1. Ensure your device has an active internet connection. Jimmy retries network requests up to three times before failing.
2. When offline, Jimmy shows the most recently cached episodes and indicates that new data can't be loaded until you reconnect.
3. Review the log file `JimmyErrors.log` located in the app's caches directory. You can share this file when reporting bugs.
4. If problems persist, reinstalling the app clears cached data that might be corrupted.

## 🤝 Collaboration & Project Rules

See [CONTRIBUTING.md](./CONTRIBUTING.md) for:
- Collaboration guidelines
- Tech stack
- Ideal project structure

Follow these rules for all development and communication in this project.

## 📄 License
This project is for personal use and educational purposes.

---

**🎉 Ready to Use**: The main app is fully functional and ready for use. The lock-screen widget is implemented and ready for Xcode setup following the guide in `WIDGET_README.md`. The Apple Watch companion is provided as sample code and needs an Xcode Watch App target to run. Version 2 is now stable with comprehensive tests and error monitoring.

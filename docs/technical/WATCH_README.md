# Jimmy Apple Watch Companion

This document explains how to add the optional Apple Watch companion app for Jimmy.

## 🚨 Current Status (Updated May 2025)

### ✅ Main App Status
- Main iOS app fully functional
- Widget implementation completed

### ⚠️ Watch App Status
- Basic watch app code provided in `WatchFiles/` directory
- Requires Xcode watchOS App target setup
- Uses `WatchConnectivity` to control playback

## 🎯 Features
- Quickly view the current episode on your watch
- Play/Pause and skip controls
- Syncs with the iPhone app using `WatchConnectivity`

## 🛠 Setup Instructions

1. **Create Watch App Target** in Xcode:
   - `File` → `New` → `Target`
   - Choose `Watch App for iOS App`
   - Product Name: `JimmyWatchApp`
2. **Move watch files** from `WatchFiles/` into the new target:
   ```
   WatchFiles/JimmyWatchApp.swift → Watch app target
   WatchFiles/WatchContentView.swift → Watch app target
   WatchFiles/WatchPlayerManager.swift → Shared with main app
   ```
3. **Enable Watch Connectivity** in both targets:
   - Add `WatchConnectivity` capability
4. **Build and run** on a paired Apple Watch device

The watch app provides a simple interface with playback controls. Full data syncing is handled by `WatchPlayerManager` using `WatchConnectivity`.

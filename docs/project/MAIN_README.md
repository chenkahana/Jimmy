# Project Documentation

This section contains the core project documentation and overview information for Jimmy.

## Files

### [Main README](./README.md) 🏠
The main project README with features overview, technology stack, and getting started information.

### [Contributing Guidelines](./CONTRIBUTING.md) 🤝
Guidelines for contributing to the Jimmy project, including workflow and style requirements.

### [App Summary](./APP_RENAME_SUMMARY.md) 📱
Brief summary of what Jimmy is and its core purpose as a minimal, queue-driven podcast app.

### [Privacy Policy](./privacyPolicy.md) 🔒
Complete privacy policy explaining data collection, usage, and user rights within the Jimmy app.

---

*These documents provide the essential information about Jimmy as a project and product.*

# Jimmy 🎙

**Built by AI, guided by Human** 🤖🧭

Jimmy is an iOS podcast player created entirely by artificial intelligence. Every line of code you see here was produced by AI, with humans only guiding the direction. The goal is a lightweight, queue‑centric app that is playful yet polished.

## Purpose
Jimmy keeps your listening queue front and center so you can quickly line up episodes, listen offline and pick up where you left off without digging through complicated menus.

## Motivation
This project explores how far AI can go in building a real, user‑facing application. Jimmy aims to show that an AI‑generated codebase can still feel thoughtful and professional, providing a smooth experience for podcast fans.

## Technology
- **Swift 5.9** and **SwiftUI** for the entire interface
- **Combine** for async data flows
- **AVFoundation** for audio playback
- **WidgetKit** and **App Groups** for lock‑screen widgets

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
- **Apple Watch companion**: _Planned but not yet available_

### User Experience
- **Search functionality**: Find podcasts and episodes quickly
- **Customizable swipe actions**: Configure swipe behaviors
- **Notifications**: Get notified of new episodes
- **iCloud sync**: Keep data synced across devices
- **Episode bookmarking**: Mark favorites to revisit later
- **Automatic cleanup**: Optionally remove played episodes

## Future Plans
Expect smarter recommendations, cross‑device syncing and an Apple Watch companion app. The AI behind Jimmy continues to evolve, so new capabilities will arrive as the project grows.

## Get in Touch
Questions or feedback? Email [chen@kahana.co.il](mailto:chen@kahana.co.il). You can also read the [Privacy Policy](./privacyPolicy.md) to understand how data is handled.

---

This repository is completely AI‑generated code. Feel free to explore the docs directory for more information about imports, widgets and other implementation notes.

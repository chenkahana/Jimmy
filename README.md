# Jimmy

A minimalist, queue-centric iOS podcast app inspired by Google Podcasts with enhanced search and subscription capabilities.

## Overview
Jimmy is a personal podcast app for iPhone, designed for simplicity, speed, and a queue-focused listening experience. It allows you to import your podcast subscriptions, discover and manage shows, and listen to episodes with a clean, modern interface.

## Features

### Core Functionality
- **Queue-centric design**: Primary focus on managing your listening queue
- **Subscription management**: Import from various sources (OPML, Apple Podcasts)  
- **Episode downloads**: Download episodes for offline listening
- **Progress tracking**: Resume playback where you left off
- **Modern UI**: Clean interface with dark mode support

### Import Options
- **OPML files**: Import subscriptions from exported files
- **Apple Podcasts**: Import directly from your Apple Podcasts library
- **Google Podcasts**: Import from Google Takeout exports

### Playback Features  
- **Variable speed**: Adjustable playback speed (0.75x to 2x)
- **Background play**: Continues playing in background
- **Audio controls**: Standard media controls and lock screen integration

### User Experience
- **Search functionality**: Find podcasts and episodes quickly
- **Customizable swipe actions**: Configure swipe behaviors
- **Notifications**: Get notified of new episodes
- **iCloud sync**: Keep data synced across devices

## Getting Started

1. Open `Jimmy.xcodeproj` in Xcode.
2. Build and run the project on your iOS device or simulator.
3. Import your podcast subscriptions using one of the available methods.
4. Start adding episodes to your queue and enjoy listening!

## Requirements
- iOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## License
This project is for personal use and educational purposes.

## Folder Structure

- Models/: Data models (Podcast, Episode, etc.)
- Views/: SwiftUI views (QueueView, PodcastListView, SettingsView, etc.)
- ViewModels/: ObservableObject classes for state management
- Services/: Logic for syncing, importing, backup, etc.
- Utilities/: Helpers (e.g., accessibility)

## Getting Started

1. Open `Jimmy.xcodeproj` in Xcode.
2. Add the folders and files above to your project.
3. Start building features as described in the PRD.

## Collaboration & Project Rules

See [CURSOR_RULES.md](./CURSOR_RULES.md) for:
- Collaboration guidelines
- Tech stack
- Ideal project structure

Follow these rules for all development and communication in this project. 
# Jimmy

A minimalist, queue-centric iOS podcast app inspired by Google Podcasts with enhanced search and subscription capabilities.

## Overview
Jimmy is a personal podcast app for iPhone, designed for simplicity, speed, and a queue-focused listening experience. It allows you to import your podcast subscriptions from multiple sources, discover new shows through web search, and listen to episodes with a clean, modern interface.

## Features

### 🔍 **Enhanced Search & Discovery**
- **Web Search**: Search Apple Podcasts directory directly from the app using iTunes Search API
- **Smart Search Scopes**: Filter between your subscriptions, discover new podcasts, or search all
- **Real-time Search**: Debounced search with live results as you type
- **Detailed Podcast Views**: Preview episodes before subscribing

### 📱 **Import Subscriptions**
- **Apple Podcasts Integration**: Import your actual Apple Podcasts subscriptions using Media Player framework
- **OPML File Support**: Import from exported OPML files (from Apple Podcasts on macOS: File > Export Subscriptions…)
- **Google Podcasts**: Import from Google Takeout export files
- **Smart Duplicate Detection**: Automatically prevents duplicate subscriptions

### 🎵 **Podcast Management**
- **Subscription Library**: View and manage your podcast subscriptions with modern UI
- **Auto-Queue**: Automatically add new episodes from favorite podcasts to your queue
- **Custom Notifications**: Get notified when new episodes are available
- **Episode Search**: Search within episodes of specific podcasts

### 🎧 **Playback & Queue**
- **Queue-Centric Design**: Primary focus on managing your listening queue
- **Episode Downloads**: Download episodes for offline listening
- **Progress Tracking**: Resume playback where you left off
- **Swipe Actions**: Customizable swipe gestures for quick actions

### ⚙️ **Modern UI & Experience**
- **Clean Design**: Minimalist interface with excellent visual hierarchy
- **Dark Mode**: System-aware dark/light mode support
- **Accessibility**: Full VoiceOver and accessibility support
- **Smooth Animations**: Polished interactions and transitions

## How to Use

### 1. **Import Your Subscriptions**
Choose from multiple import options:
- **Apple Podcasts**: Directly imports from your Apple Podcasts library (requires media library permission)
- **OPML File**: Export from Apple Podcasts (macOS: File > Export Subscriptions…) and import
- **Google Podcasts**: Use your Google Takeout export file

### 2. **Discover New Podcasts**
- Use the dedicated **Search** tab to find new podcasts
- Search across the entire Apple Podcasts directory
- Preview episodes before subscribing
- One-tap subscription with duplicate prevention

### 3. **Manage Your Library**
- View all subscriptions in the **Library** tab
- Toggle auto-queue and notifications per podcast
- Search within your subscribed podcasts
- Access episodes with detailed information

### 4. **Queue & Playback**
- Add episodes to your queue for continuous listening
- Download episodes for offline access
- Control playback with standard media controls
- Track progress across episodes

## Technical Requirements
- **iOS 15+ or macOS 12+**
- **SwiftUI Framework**
- **Media Library Access** (for Apple Podcasts import)
- **Network Access** (for podcast discovery and streaming)

## Privacy & Permissions
- **Media Library**: Optional, only for importing Apple Podcasts subscriptions
- **Network**: Required for podcast discovery, episode streaming, and artwork loading
- **Notifications**: Optional, for new episode alerts

## Architecture

### Service Layer
- **iTunesSearchService**: Handles podcast discovery via Apple's iTunes Search API
- **ApplePodcastService**: Manages Apple Podcasts subscription import
- **PodcastService**: Core podcast and episode management
- **QueueViewModel**: Manages playback queue and episode state

### Data Models
- **Podcast**: Core podcast information with RSS feed URLs
- **Episode**: Individual episode data with playback state
- **PodcastSearchResult**: Search results from iTunes API

### User Interface
- **ContentView**: Main tab navigation
- **PodcastSearchView**: Web search and discovery interface
- **PodcastListView**: Subscription library management
- **QueueView**: Playback queue management
- **EpisodePlayerView**: Individual episode playback

## Folder Structure

```
Jimmy/
├── Models/           # Data models (Podcast, Episode, etc.)
├── Views/            # SwiftUI views and UI components
├── ViewModels/       # ObservableObject classes for state management
├── Services/         # Business logic and API integration
└── Utilities/        # Helpers, parsers, and extensions
```

## Getting Started

1. Open `Jimmy.xcodeproj` in Xcode
2. Build and run the project
3. Import your subscriptions using one of the available methods
4. Start discovering and listening to podcasts!

## Roadmap
- **Enhanced Player**: Video podcast support, sleep timer, playback speed controls
- **Smart Recommendations**: Personalized podcast suggestions
- **Social Features**: Share episodes and create collaborative playlists
- **Cross-Platform Sync**: iCloud sync for seamless experience across devices
- **Advanced Analytics**: Detailed listening statistics and insights

## License
This project is for personal use and learning. See LICENSE for details. 
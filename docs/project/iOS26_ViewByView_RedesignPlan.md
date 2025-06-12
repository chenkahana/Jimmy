# iOS 26 Liquid Glass - View-by-View Redesign Plan

## 1. Core Navigation & Structure

### 1.1 ContentView.swift
**Current:** Standard tab-based navigation with custom tab bar
**Redesign:**
- **Background:** Dynamic gradient backdrop that shifts based on content
- **Tab Switching:** Smooth cross-dissolve transitions with spring animations
- **Loading State:** Liquid morphing animation instead of static progress view
- **Implementation:**
  ```swift
  .background {
      LinearGradient(
          colors: [Color.clear, Color.accentColor.opacity(0.05)],
          startPoint: .top, endPoint: .bottom
      )
      .background(.ultraThinMaterial)
  }
  ```

### 1.2 CustomTabBar (in ContentView)
**Current:** Standard horizontal tab bar with icons
**Redesign:**
- **Shape:** Floating capsule with rounded corners (24pt radius)
- **Material:** `.ultraThinMaterial` with subtle shadow
- **Behavior:** 
  - Shrinks to 60% height on scroll up
  - Reduces opacity to 0.8 when scrolling
  - Expands back with spring animation on scroll down
- **Position:** Floating 16pt above bottom safe area
- **Implementation:**
  ```swift
  .background {
      Capsule()
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
  }
  .scaleEffect(y: isScrolling ? 0.6 : 1.0)
  .opacity(isScrolling ? 0.8 : 1.0)
  ```

## 2. Discovery & Search Views

### 2.1 DiscoverView.swift
**Current:** Grid-based podcast discovery with categories
**Redesign:**
- **Header:** Large translucent title with parallax effect
- **Categories:** Floating cards with `.thinMaterial` backgrounds
- **Featured Section:** Hero card with frosted overlay and depth
- **Scroll Behavior:** Parallax background movement, staggered card animations
- **Implementation:**
  ```swift
  ScrollView {
      LazyVStack(spacing: 20) {
          // Hero section with parallax
          GeometryReader { geometry in
              FeaturedPodcastCard()
                  .offset(y: geometry.frame(in: .global).minY * 0.3)
          }
          .frame(height: 300)
          
          // Category cards with staggered animation
          LazyVGrid(columns: columns, spacing: 16) {
              ForEach(categories.indices, id: \.self) { index in
                  CategoryCard(category: categories[index])
                      .transition(.asymmetric(
                          insertion: .scale.combined(with: .opacity),
                          removal: .opacity
                      ))
                      .animation(.spring(response: 0.6, dampingFraction: 0.8)
                          .delay(Double(index) * 0.1), value: categories)
              }
          }
      }
  }
  .background(.ultraThinMaterial)
  ```

### 2.2 PodcastSearchView.swift
**Current:** Standard search interface with results list
**Redesign:**
- **Search Bar:** Floating capsule with `.regularMaterial` background
- **Results:** Cards with frosted backgrounds and hover effects
- **Empty State:** Animated glass morphing illustration
- **Suggestions:** Floating bubble tags with spring interactions

### 2.3 RecommendedPodcastItem.swift & LargeRecommendedPodcastItem.swift
**Current:** Standard card layouts
**Redesign:**
- **Background:** `.thinMaterial` with rounded corners (16pt)
- **Image:** Frosted overlay with subtle glow effect
- **Interaction:** Scale + brightness animation on tap
- **Shadow:** Soft drop shadow for depth perception

## 3. Library & Content Views

### 3.1 LibraryView.swift
**Current:** List-based podcast library
**Redesign:**
- **Header:** Sticky translucent header with search integration
- **Podcast Grid:** Floating cards with material backgrounds
- **Filter Bar:** Horizontal scrolling capsule buttons
- **Pull-to-Refresh:** Liquid morphing animation
- **Implementation:**
  ```swift
  NavigationView {
      ScrollView {
          LazyVGrid(columns: adaptiveColumns, spacing: 16) {
              ForEach(podcasts) { podcast in
                  PodcastLibraryCard(podcast: podcast)
                      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                      .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
              }
          }
          .padding(.horizontal)
      }
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.large)
      .background(.ultraThinMaterial)
  }
  ```

### 3.2 PodcastDetailView.swift
**Current:** Detailed podcast view with episode list
**Redesign:**
- **Hero Section:** Parallax podcast artwork with frosted info overlay
- **Action Buttons:** Floating capsule buttons with material fills
- **Episode List:** Cards with subtle material backgrounds
- **Scroll Effects:** Header collapse with smooth material transitions

### 3.3 EpisodeDetailView.swift
**Current:** Episode information and playback controls
**Redesign:**
- **Background:** Blurred episode artwork as backdrop
- **Content Card:** Floating `.regularMaterial` card with rounded corners
- **Play Button:** Large circular button with glow effect
- **Description:** Expandable text with smooth height animation

### 3.4 EpisodeListView.swift
**Current:** Simple episode list
**Redesign:**
- **Cards:** Individual episode cards with `.thinMaterial` backgrounds
- **Artwork:** Rounded corners with subtle shadow
- **Progress Indicators:** Liquid progress bars with gradient fills
- **Swipe Actions:** Reveal actions with spring animations

## 4. Playback & Audio Views

### 4.1 CurrentPlayView.swift
**Current:** Full-screen now playing interface
**Redesign:**
- **Background:** Dynamic blur based on artwork colors
- **Artwork:** Floating with soft shadow and subtle rotation on play
- **Controls:** Capsule-shaped buttons with material fills
- **Progress Bar:** Liquid-style progress with glow effect
- **Lyrics/Info:** Sliding cards with `.regularMaterial` backgrounds

### 4.2 MiniPlayerView.swift
**Current:** Bottom mini player bar
**Redesign:**
- **Shape:** Floating capsule above tab bar
- **Material:** `.ultraThinMaterial` with subtle shadow
- **Behavior:** Swipe to dismiss with spring animation
- **Expansion:** Smooth transition to full player with matched geometry
- **Implementation:**
  ```swift
  HStack {
      // Content
  }
  .padding(.horizontal, 16)
  .padding(.vertical, 12)
  .background {
      Capsule()
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
  }
  .padding(.horizontal, 16)
  .padding(.bottom, 100) // Above floating tab bar
  ```

### 4.3 AudioPlayerView.swift & EpisodePlayerView.swift
**Current:** Standard playback controls
**Redesign:**
- **Buttons:** Circular with material fills and glow effects
- **Sliders:** Custom liquid-style sliders with haptic feedback
- **Volume Control:** Floating volume slider with auto-hide

## 5. Queue & Management Views

### 5.1 QueueView.swift
**Current:** Episode queue list
**Redesign:**
- **Header:** Floating "Up Next" title with material background
- **Episodes:** Draggable cards with reorder animations
- **Empty State:** Animated illustration with glass morphing
- **Clear Button:** Floating action button with confirmation animation

### 5.2 QueueEpisodeCardView.swift
**Current:** Queue episode representation
**Redesign:**
- **Background:** `.thinMaterial` with rounded corners
- **Drag Handle:** Subtle material indicator
- **Reorder Animation:** Smooth spring-based movement
- **Remove Action:** Swipe with liquid dissolve animation

## 6. Settings & Utility Views

### 6.1 SettingsView.swift
**Current:** Standard settings list
**Redesign:**
- **Sections:** Grouped cards with material backgrounds
- **Toggles:** Custom switches with glow effects
- **Navigation:** Smooth push/pop with material transitions
- **Profile Section:** Hero card with user info and frosted background

### 6.2 CacheManagementView.swift
**Current:** Storage management interface
**Redesign:**
- **Storage Bars:** Liquid progress indicators with color coding
- **Action Buttons:** Floating capsule buttons with confirmation states
- **Statistics:** Cards with animated number counters

### 6.3 AnalyticsView.swift
**Current:** App analytics display
**Redesign:**
- **Charts:** Floating chart cards with material backgrounds
- **Metrics:** Animated counters with glow effects
- **Time Filters:** Segmented control with liquid selection indicator

## 7. Component Views

### 7.1 EpisodeRowView.swift
**Current:** Episode list item
**Redesign:**
- **Background:** `.thinMaterial` with rounded corners (12pt)
- **Artwork:** Rounded with subtle shadow
- **Progress:** Liquid progress bar at bottom
- **Actions:** Reveal on swipe with spring animations
- **Interaction:** Scale + brightness feedback on tap

### 7.2 LoadingIndicator.swift
**Current:** Standard loading spinner
**Redesign:**
- **Animation:** Liquid morphing shapes with color transitions
- **Backdrop:** Subtle material blur
- **States:** Different animations for different loading types

### 7.3 CachedAsyncImage.swift
**Current:** Image loading component
**Redesign:**
- **Placeholder:** Animated gradient shimmer
- **Loading:** Liquid morphing animation
- **Error State:** Subtle material background with icon
- **Transitions:** Smooth fade-in with scale animation

## 8. Implementation Utilities

### 8.1 New Material Style Modifiers
```swift
// Jimmy/Utilities/MaterialStyle.swift
extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    func floatingElement() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}
```

### 8.2 Scroll Offset Tracking
```swift
// Jimmy/Utilities/ScrollOffsetPreference.swift
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

## 9. Animation Specifications

### Spring Animations
- **Default:** `spring(response: 0.6, dampingFraction: 0.8)`
- **Quick:** `spring(response: 0.3, dampingFraction: 0.9)`
- **Bouncy:** `spring(response: 0.8, dampingFraction: 0.6)`

### Material Transitions
- **Opacity:** 0.3 second ease-in-out
- **Scale:** 0.4 second spring animation
- **Position:** 0.5 second spring with stagger

### Scroll Behaviors
- **Tab Bar Shrink:** Triggered at 50pt scroll offset
- **Header Collapse:** Smooth transition over 100pt range
- **Parallax:** 0.3x scroll speed for background elements

---
*End of View-by-View Redesign Plan* 
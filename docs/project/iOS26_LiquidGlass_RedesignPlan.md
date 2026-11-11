# iOS 26 Liquid Glass Redesign Plan

## 1. Overview
This document defines the redesign of the Jimmy Podcast App to adopt the modern iOS 26 "liquid glass" aesthetic—leveraging frosted translucency, depth, motion, and layered materials for an immersive experience.

## 2. Objectives
- Introduce frosted glass effects and depth across core UI components
- Elevate navigation through floating, rounded elements with dynamic sizing and opacity
- Enhance user engagement with subtle motion and responsive feedback
- Maintain performance and accessibility standards

## 3. Design Principles
- **Frosted Translucency:** Use `.ultraThinMaterial`, `.thinMaterial` backgrounds over blurred content
- **Depth & Elevation:** Floating components with soft shadows and rounded corners
- **Motion & Animation:** Spring-based transitions, parallax scroll effects, dynamic resizing
- **Adaptive Opacity:** Components fade and shrink on scroll for focus
- **Accessibility:** Preserve legibility, support Dynamic Type, maintain contrast ratios

## 4. Key Components & Redesign Details

### 4.1 Tab Bar
- **Appearance:** Capsule-shaped, floating above content, blurred `ultraThinMaterial` background
- **Behavior:**
  - Shrinks in height and reduces opacity on upward scroll
  - Expands and regains opacity on downward scroll or idle
- **Elevation:** Subtle shadow for depth
- **Implementation:** Replace default `TabView` bar with custom `TabBarView` using `GeometryReader` and `VisualEffectView` wrappers

### 4.2 Navigation Bar
- **Appearance:** Translucent `.regularMaterial` backdrop, large title style
- **Behavior:** Collapsible on content scroll with smooth fade and size transition
- **Implementation:** Custom `NavigationBarView` modifier, integrate with `ScrollView` offset tracking

### 4.3 Content Cards (EpisodeRowView, PodcastRowView)
- **Appearance:** Rounded corners (16 pt), `.thinMaterial` background, drop shadow
- **Interaction:** Tap highlight with scale and brightness shift
- **Backdrop:** Blur behind featured images

### 4.4 Sheets & Modals
- **Appearance:** Rounded top corners (20 pt), blurred backdrop, translucent drag indicator
- **Motion:** Spring animation on presentation/dismissal, dimmed background overlay

### 4.5 Player Controls (MiniPlayerView, CurrentPlayView)
- **Appearance:** Floating control bar with `.ultraThinMaterial`, rounded capsule
- **Behavior:** Expandable on tap, swipe to dismiss, animated transition

### 4.6 Buttons & Controls
- **Style:** Capsule-shaped buttons with material fills, accent-tinted icons
- **States:** Pressed, disabled visual feedback via blur intensity and opacity

## 5. Implementation Details
- **SwiftUI:** Use `VisualEffectView` wrappers for material backgrounds
- **View Modifiers:** Create reusable `MaterialStyle` and `GlassComponent` modifiers
- **Scroll Effects:** Leverage `GeometryReader` and `PreferenceKey` to track offsets
- **Threading:** Ensure UI updates on `@MainActor` via `Task { @MainActor in ... }`
- **Performance:** Limit overlapping blur layers, reuse material views, monitor via `UIPerformanceManager`
- **Fallbacks:** Provide semi-transparent solid colors for iOS 15/16

## 6. File Impact & Dependencies
| Component                 | File Path                                                    |
|---------------------------|--------------------------------------------------------------|
| Custom Tab Bar            | `Jimmy/Views/Components/TabBarView.swift`                    |
| Custom Navigation Bar     | `Jimmy/Views/Components/NavigationBarView.swift`             |
| Episode & Podcast Rows    | `Jimmy/Views/EpisodeRowView.swift`, `PodcastRowView.swift`   |
| Sheets & Modals           | `Jimmy/Views/ModalViews/…`                                   |
| Player Controls           | `Jimmy/Views/MiniPlayerView.swift`, `CurrentPlayView.swift`  |
| Material Styles           | `Jimmy/Utilities/MaterialStyle.swift`                        |
| Scroll Tracking Helpers   | `Jimmy/Utilities/ScrollOffsetPreference.swift`               |
| View Model Updates        | `Jimmy/ViewModels/*` (ensure `@MainActor` updates)           |

## 7. Timeline & Milestones
| Week | Goals                                                  |
|------|--------------------------------------------------------|
| 1    | Research, prototypes for TabBar & NavBar               |
| 2    | Integrate TabBarView & NavigationBarView               |
| 3    | Redesign content cards and player controls             |
| 4    | Revamp sheets, modals, buttons; refine animations      |
| 5    | Accessibility review, adjust contrast and spacing      |
| 6    | Performance profiling, optimize blur layer usage       |
| 7    | Beta testing, feedback iteration, final polish         |

## 8. Testing & QA
- **Visual QA:** Verify material effects across light/dark modes
- **UI Tests:** Automate scroll shrink/expand, sheet animations
- **Performance:** Profile blur layers with Instruments, monitor FPS
- **Accessibility:** Dynamic Type, VoiceOver labeling, contrast checks

---
*End of iOS 26 Liquid Glass Redesign Plan* 
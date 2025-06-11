Queue Tab Redesign Plan for iOS App

1. Overview

Objective: Build a fully interactive, visually polished Queue Tab aligned with iOS 26 design language. This document provides detailed component specifications, view hierarchies, data flow, interaction logic, and animation guidelines, suitable for direct consumption by a developer or UI generation model.

2. Architecture & Data Model

Data Source: QueueViewModel exposing episodes: [Episode] and currentEpisode: Episode?.

Episode Model:

struct Episode: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let artworkURL: URL
    let duration: TimeInterval
    var playedTime: TimeInterval
}

View Hierarchy:

QueueTabView
└── VStack
    ├── QueueHeaderView
    └── LazyVStack {
          ForEach(viewModel.episodes) { episode in
              EpisodeCellView(episode: episode, isPlaying: episode.id == viewModel.currentEpisode?.id)
                  .gesture(dragGesture)
                  .simultaneousGesture(swipeGesture)
          }
      }

3. UI Components

3.1 QueueHeaderView

Shows title “Up Next” and subtitle “(viewModel.episodes.count) items • (totalRemainingTime) left”

Font: SF Pro Semibold 20pt, dynamic color.

Padding: 16pt top, bottom 8pt.

3.2 EpisodeCellView

Container: RoundedRectangle(cornerRadius: 12) background with drop shadow (color: black 8% opacity, radius: 4, y-offset: 2).

Layout: HStack(spacing: 12)

Artwork: AsyncImage(url: episode.artworkURL)

Frame: 56×56, corner radius: 8.

Text Stack: VStack(alignment: .leading, spacing: 4)

TitleLabel: Text(episode.title), font: SF Pro Bold 16pt, lineLimit: 2.

ArtistLabel: Text(episode.artist), font: SF Pro Regular 14pt, foreground: secondary.

MetadataRow: HStack(spacing: 8)

Text(formattedDuration) (e.g., “45:30”), font: SF Pro Regular 12pt.

ProgressView(value: episode.playedTime / episode.duration)

Style: custom (.progressViewStyle(CarouselProgressStyle())), height: 2pt.

Drag Handle: Image(systemName: "line.horizontal.3") color: tertiary.

Sizing: Height: 80pt; horizontal padding: 16pt; vertical padding: 8pt.

Highlight: If isPlaying == true, background tint: accent color light 10%.

4. Interaction Logic

4.1 Drag-and-Drop Reordering

Enable Drag on non-playing cells.

On onLongPressGesture:

Call viewModel.beginDrag(episode:) → store draggedEpisode.

Provide haptic .medium.

On DragGesture update:

Determine index under drag location via hitTest on cell frames.

Call viewModel.moveEpisode(from:originalIndex, to:newIndex).

On gesture end:

Call viewModel.endDrag() → persist final order.

Haptic .success.

4.2 Tap to Play

On TapGesture on any cell:

Call viewModel.play(episode:).

Logic in ViewModel:

func play(episode: Episode) {
  guard let index = episodes.firstIndex(of: episode) else { return }
  // Remove at index, insert at 0
  episodes.remove(at: index)
  episodes.insert(episode, at: 0)
  currentEpisode = episode
}

Animate cell moving to top: use withAnimation(.spring(response:0.4, dampingFraction:0.8)).

Update player header.

4.3 Swipe Actions

Gesture: DragGesture(minimumDistance: 20, coordinateSpace: .local) on each cell.

Thresholds:

Partial: ±60pt → reveal action buttons.

Full: ±150pt → trigger action.

Direction

Partial Reveal

Full Swipe Action

Swipe Right

Show “Move to Top”

Move episode to index 1

Swipe Left

Show “Move to Bottom”

Move episode to last index

Swipe Either

⏳

Delete episode

Implementation:

let offset = drag.translation.width
if abs(offset) > fullThreshold {
  if offset > 0 { viewModel.remove(episode) } else { viewModel.remove(episode) }
} else if offset > partialThreshold {
  showMoveToTopButton()
} else if offset < -partialThreshold {
  showMoveToBottomButton()
}

ViewModel Actions:

moveToTop(episode:): place at index 1.

moveToBottom(episode:): place at last index.

remove(episode:): remove from episodes array.

5. Animations & Feedback

General Timing: 0.3–0.5s with .spring for layout changes.

Drag Feedback: Placeholder cell with dashed border where it will drop.

Swipe Feedback: Background color and icon slide in proportionally.

Haptics:

Lift drag: .medium

Drop reorder: .success

Swipe action complete: .light

6. Theming & Styles

Fonts: SF Pro, dynamic type support.

Colors: Use semantic colors:

Background: systemBackground

Cell BG: secondarySystemBackground

Accent: tintColor

Swipe BG: .systemBlue, .systemGreen, .systemRed

Icons: SF Symbols (arrow.up, arrow.down, trash).

Spacing: 16pt horizontal, 8pt vertical.

7. Accessibility & Localization

VoiceOver:

Episode cell: "Episode Title by Artist, X minutes, Y minutes remaining."

Buttons: "Move to top", "Move to bottom", "Remove from queue".

Dynamic Type: All text scales.

Localization: Strings in Localizable.strings.

8. Testing & Validation

Unit Tests:

ViewModel reorder, play, swipe actions.

UI Tests:

Drag reorder reflects data change.

Tap moves episode to top.

Swipe actions reveal correct buttons and perform actions.

Accessibility Tests:

VoiceOver reads labels correctly.
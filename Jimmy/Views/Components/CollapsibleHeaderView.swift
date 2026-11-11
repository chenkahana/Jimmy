import SwiftUI

/// A reusable large artwork header that collapses into a sticky bar as the user scrolls.
///
/// - Parameters:
///   - podcast: The podcast whose artwork & metadata are displayed.
///   - headerHeight: The maximum expanded height of the header.
///   - minHeight: The height at which the header is fully collapsed (should match sticky header height).
///   - scrollOffset: The current vertical scroll offset of the parent `ScrollView` (negative when scrolling up).
///
/// The view renders:
/// 1. Full-width square artwork background with subtle blur.
/// 2. Gradient overlay to fade artwork into the view background.
/// 3. Center-aligned title & author that fade in as the header collapses.
public struct CollapsibleHeaderView: View {
    // MARK: - Input
    public let podcast: Podcast
    public let headerHeight: CGFloat
    public let minHeight: CGFloat
    public let scrollOffset: CGFloat
    
    // MARK: - Constants
    private let artworkVerticalOffset: CGFloat = 10 // Changed from 50 to 40 to move up 10pt

    // MARK: - Derived Metrics
    private var collapseProgress: CGFloat {
        let totalCollapse = headerHeight - minHeight
        guard totalCollapse > 0 else { return 1 }
        let progress = (-scrollOffset) / totalCollapse
        return progress.clamped(to: 0...1)
    }

    // Down-pull parallax (positive offset) - add 50pt to maintain parallax after artwork offset
    private var pullOffset: CGFloat {
        max(scrollOffset + artworkVerticalOffset, 0)
    }

    public init(podcast: Podcast,
                headerHeight: CGFloat = 400,
                minHeight: CGFloat = 80,
                scrollOffset: CGFloat) {
        self.podcast = podcast
        self.headerHeight = headerHeight
        self.minHeight = minHeight
        self.scrollOffset = scrollOffset
    }

    // MARK: - Body
    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Full-screen background artwork extending above dynamic island
                BulletproofAsyncImagePhase(url: podcast.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(
                    width: geometry.size.width * 1.05,
                    height: headerHeight + pullOffset + geometry.safeAreaInsets.top
                )
                .offset(x: geometry.size.width * -0.025, y: -pullOffset - geometry.safeAreaInsets.top + artworkVerticalOffset ) // Add artwork offset
                // Overlay a blurred copy masked so only the lower part is blurred
                .overlay(
                    BulletproofAsyncImagePhase(url: podcast.artworkURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .blur(radius: 20)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),   // 0-50% stays sharp
                                .init(color: .clear, location: 0.55),  // slight buffer
                                .init(color: .black, location: 0.75), // begin blur
                                .init(color: .black, location: 1.0)   // fully blurred at bottom
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(1.0)
                    .frame(
                        width: geometry.size.width * 1.05,
                        height: headerHeight + pullOffset + geometry.safeAreaInsets.top 
                    )
                    .offset(x: geometry.size.width * -0.025, y: -pullOffset - geometry.safeAreaInsets.top - 25 + artworkVerticalOffset) // Add artwork offset
                )

                // Gradient overlay to dissolve into background
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.clear,
                        Color(.systemBackground).opacity(0.3),
                        Color(.systemBackground).opacity(0.7),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: headerHeight)
            }
        }
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity) // Ensure full-width across all devices
        .clipped()
        .ignoresSafeArea(.all, edges: .top) // extend behind status bar/dynamic island
    }
}

// MARK: - Utility
private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

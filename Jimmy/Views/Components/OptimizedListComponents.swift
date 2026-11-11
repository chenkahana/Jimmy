import SwiftUI
import UIKit

// MARK: - Optimized List Rendering Components

/// High-performance list view optimized for smooth scrolling with large datasets
/// Uses lazy loading, view recycling, and minimal state updates
struct OptimizedEpisodeList<Content: View>: View {
    let episodes: [EpisodeWithStatus]
    let content: (EpisodeWithStatus) -> Content
    
    // Performance optimizations
    @State private var visibleRange: Range<Int> = 0..<20
    private let bufferSize = 10
    private let itemHeight: CGFloat = 80
    
    init(
        episodes: [EpisodeWithStatus],
        @ViewBuilder content: @escaping (EpisodeWithStatus) -> Content
    ) {
        self.episodes = episodes
        self.content = content
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 8) {
                ForEach(visibleEpisodes, id: \.id) { episode in
                    content(episode)
                        .id(episode.id)
                        .onAppear {
                            updateVisibleRange(for: episode)
                        }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
    
    private var visibleEpisodes: [EpisodeWithStatus] {
        let startIndex = max(0, visibleRange.lowerBound - bufferSize)
        let endIndex = min(episodes.count, visibleRange.upperBound + bufferSize)
        
        guard startIndex < episodes.count && endIndex > startIndex else {
            return []
        }
        
        return Array(episodes[startIndex..<endIndex])
    }
    
    private func updateVisibleRange(for episode: EpisodeWithStatus) {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else {
            return
        }
        
        let newStart = max(0, index - bufferSize)
        let newEnd = min(episodes.count, index + bufferSize)
        
        if newStart != visibleRange.lowerBound || newEnd != visibleRange.upperBound {
            visibleRange = newStart..<newEnd
        }
    }
}

/// Optimized podcast grid with efficient image loading and smooth animations
struct OptimizedPodcastGrid: View {
    let podcasts: [Podcast]
    let onPodcastTap: (Podcast) -> Void
    let onUnsubscribe: (Podcast) -> Void
    let isEditMode: Bool
    
    // Grid configuration optimized for performance
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(podcasts, id: \.id) { podcast in
                OptimizedPodcastCard(
                    podcast: podcast,
                    isEditMode: isEditMode,
                    onUnsubscribe: { onUnsubscribe(podcast) }
                )
                .onTapGesture {
                    if !isEditMode {
                        onPodcastTap(podcast)
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: podcasts.count)
    }
}



// MARK: - Smooth Animation Helpers

extension Animation {
    /// Optimized spring animation for UI elements
    static var smoothSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)
    }
    
    /// Fast easing for quick interactions
    static var quickEase: Animation {
        .easeInOut(duration: 0.2)
    }
    
    /// Gentle animation for content changes
    static var gentleTransition: Animation {
        .easeInOut(duration: 0.3)
    }
}

// MARK: - Performance Monitoring View Modifier

struct PerformanceOptimizedModifier: ViewModifier {
    @StateObject private var performanceManager = UIPerformanceManager.shared
    
    func body(content: Content) -> some View {
        content
            .drawingGroup(opaque: false, colorMode: .nonLinear)
            .onAppear {
                performanceManager.enableHighPerformanceScrolling()
            }
            .onDisappear {
                performanceManager.disableHighPerformanceScrolling()
            }
    }
}

extension View {
    /// Apply performance optimizations to any view
    func optimizePerformance() -> some View {
        modifier(PerformanceOptimizedModifier())
    }
}

// MARK: - Skeleton Loading Components

/// Smooth skeleton loading animation for better perceived performance
struct SkeletonLoadingView: View {
    @State private var isAnimating = false
    
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    init(width: CGFloat = 200, height: CGFloat = 20, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemGray5),
                        Color(.systemGray4),
                        Color(.systemGray5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: height)
            .scaleEffect(x: isAnimating ? 1.1 : 0.9, y: 1.0)
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

/// Skeleton loading for podcast cards
struct PodcastCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            // Artwork skeleton
            SkeletonLoadingView(width: 120, height: 120, cornerRadius: 12)
            
            // Title skeleton
            VStack(spacing: 4) {
                SkeletonLoadingView(width: 100, height: 12, cornerRadius: 2)
                SkeletonLoadingView(width: 80, height: 12, cornerRadius: 2)
            }
        }
    }
}

/// Skeleton loading for episode rows
struct EpisodeRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Artwork skeleton
            SkeletonLoadingView(width: 60, height: 60, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 6) {
                // Title skeleton
                SkeletonLoadingView(width: 200, height: 16, cornerRadius: 2)
                
                // Subtitle skeleton
                SkeletonLoadingView(width: 150, height: 12, cornerRadius: 2)
                
                // Progress skeleton
                SkeletonLoadingView(width: 100, height: 8, cornerRadius: 4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
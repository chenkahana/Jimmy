import SwiftUI

/// 🌊 Liquid Skeleton Views - Beautiful loading states that feel magical
/// These create the illusion of instant loading by showing gorgeous animated placeholders

struct LiquidSkeletonView: View {
    let style: SkeletonStyle
    @State private var animationPhase: CGFloat = 0
    @State private var gradientOffset: CGFloat = -1
    
    enum SkeletonStyle {
        case podcastCard
        case episodeRow
        case libraryGrid
        case nowPlayingCard
        case searchResult
        case compactRow
        
        var height: CGFloat {
            switch self {
            case .podcastCard: return 200
            case .episodeRow: return 80
            case .libraryGrid: return 160
            case .nowPlayingCard: return 120
            case .searchResult: return 60
            case .compactRow: return 50
            }
        }
    }
    
    var body: some View {
        Group {
            switch style {
            case .podcastCard:
                podcastCardSkeleton
            case .episodeRow:
                episodeRowSkeleton
            case .libraryGrid:
                libraryGridSkeleton
            case .nowPlayingCard:
                nowPlayingCardSkeleton
            case .searchResult:
                searchResultSkeleton
            case .compactRow:
                compactRowSkeleton
            }
        }
        .onAppear {
            startLiquidAnimation()
        }
    }
    
    // MARK: - Skeleton Styles
    
    private var podcastCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artwork placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(gradientShimmer)
                .aspectRatio(1, contentMode: .fit)
            
            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(gradientShimmer)
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                
                // Subtitle placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradientShimmer)
                    .frame(height: 12)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: 0.7, anchor: .leading)
                
                // Stats placeholder
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gradientShimmer)
                        .frame(width: 40, height: 10)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gradientShimmer)
                        .frame(width: 60, height: 10)
                }
            }
        }
        .frame(height: style.height)
    }
    
    private var episodeRowSkeleton: some View {
        HStack(spacing: 12) {
            // Episode artwork
            RoundedRectangle(cornerRadius: 8)
                .fill(gradientShimmer)
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 6) {
                // Episode title
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradientShimmer)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                
                // Episode description
                RoundedRectangle(cornerRadius: 3)
                    .fill(gradientShimmer)
                    .frame(height: 11)
                    .scaleEffect(x: 0.8, anchor: .leading)
                
                HStack {
                    // Duration
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradientShimmer)
                        .frame(width: 45, height: 10)
                    
                    Spacer()
                    
                    // Date
                    RoundedRectangle(cornerRadius: 3)
                        .fill(gradientShimmer)
                        .frame(width: 50, height: 10)
                }
            }
            
            // Progress indicator placeholder
            Circle()
                .fill(gradientShimmer)
                .frame(width: 20, height: 20)
        }
        .frame(height: style.height)
        .padding(.horizontal, 16)
    }
    
    private var libraryGridSkeleton: some View {
        VStack(spacing: 8) {
            // Artwork
            RoundedRectangle(cornerRadius: 12)
                .fill(gradientShimmer)
                .aspectRatio(1, contentMode: .fit)
            
            // Title
            RoundedRectangle(cornerRadius: 4)
                .fill(gradientShimmer)
                .frame(height: 12)
                .scaleEffect(x: 0.9, anchor: .center)
            
            // Subtitle
            RoundedRectangle(cornerRadius: 3)
                .fill(gradientShimmer)
                .frame(height: 10)
                .scaleEffect(x: 0.6, anchor: .center)
        }
        .frame(height: style.height)
    }
    
    private var nowPlayingCardSkeleton: some View {
        HStack(spacing: 16) {
            // Large artwork
            RoundedRectangle(cornerRadius: 12)
                .fill(gradientShimmer)
                .frame(width: 80, height: 80)
            
            VStack(alignment: .leading, spacing: 8) {
                // Title
                RoundedRectangle(cornerRadius: 4)
                    .fill(gradientShimmer)
                    .frame(height: 16)
                
                // Artist
                RoundedRectangle(cornerRadius: 3)
                    .fill(gradientShimmer)
                    .frame(height: 12)
                    .scaleEffect(x: 0.7, anchor: .leading)
                
                // Progress bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(gradientShimmer)
                    .frame(height: 4)
                    .scaleEffect(x: 0.6, anchor: .leading)
            }
            
            Spacer()
            
            // Play button
            Circle()
                .fill(gradientShimmer)
                .frame(width: 44, height: 44)
        }
        .frame(height: style.height)
        .padding(.horizontal, 16)
    }
    
    private var searchResultSkeleton: some View {
        HStack(spacing: 12) {
            // Small artwork
            RoundedRectangle(cornerRadius: 6)
                .fill(gradientShimmer)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                RoundedRectangle(cornerRadius: 3)
                    .fill(gradientShimmer)
                    .frame(height: 12)
                
                // Subtitle
                RoundedRectangle(cornerRadius: 2)
                    .fill(gradientShimmer)
                    .frame(height: 10)
                    .scaleEffect(x: 0.6, anchor: .leading)
            }
            
            Spacer()
        }
        .frame(height: style.height)
        .padding(.horizontal, 16)
    }
    
    private var compactRowSkeleton: some View {
        HStack(spacing: 10) {
            // Small indicator
            Circle()
                .fill(gradientShimmer)
                .frame(width: 30, height: 30)
            
            // Text content
            VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(gradientShimmer)
                    .frame(height: 11)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(gradientShimmer)
                    .frame(height: 9)
                    .scaleEffect(x: 0.7, anchor: .leading)
            }
            
            Spacer()
        }
        .frame(height: style.height)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Liquid Animation
    
    private var gradientShimmer: LinearGradient {
        if UIAccessibility.isReduceMotionEnabled {
            // Static gradient for Reduce Motion
            return LinearGradient(
                colors: [
                    Color.gray.opacity(0.2),
                    Color.gray.opacity(0.3),
                    Color.gray.opacity(0.2)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            // Animated shimmer gradient
            return LinearGradient(
                colors: [
                    Color.gray.opacity(0.3),
                    Color.white.opacity(0.8),
                    Color.gray.opacity(0.3)
                ],
                startPoint: UnitPoint(x: gradientOffset, y: 0.5),
                endPoint: UnitPoint(x: gradientOffset + 0.3, y: 0.5)
            )
        }
    }
    
    private func startLiquidAnimation() {
        // Respect Reduce Motion accessibility setting
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            gradientOffset = 1.3
        }
        
        // Add subtle scale animation for organic feel
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            animationPhase = 1.0
        }
    }
}

// MARK: - Skeleton Collection Views

struct SkeletonPodcastGrid: View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<9, id: \.self) { _ in
                LiquidSkeletonView(style: .libraryGrid)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, 16)
    }
}

struct SkeletonEpisodeList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { index in
                LiquidSkeletonView(style: .episodeRow)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: index)
                
                if index < 7 {
                    Divider()
                        .opacity(0.3)
                }
            }
        }
    }
}

struct SkeletonNowPlaying: View {
    var body: some View {
        LiquidSkeletonView(style: .nowPlayingCard)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .opacity
            ))
    }
}

// MARK: - Smart Loading States

struct SmartLoadingState<Content: View>: View {
    let isLoading: Bool
    let skeletonStyle: LiquidSkeletonView.SkeletonStyle
    let skeletonCount: Int
    @ViewBuilder let content: () -> Content
    

    
    init(
        isLoading: Bool,
        skeleton: LiquidSkeletonView.SkeletonStyle,
        count: Int = 1,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.skeletonStyle = skeleton
        self.skeletonCount = count
        self.content = content
    }
    
    private var adaptiveSkeletonCount: Int {
        // Use the requested skeleton count directly
        skeletonCount
    }
    
    private var adaptiveAnimation: Animation {
        // Use spring animation unless Reduce Motion is enabled
        if UIAccessibility.isReduceMotionEnabled {
            return .easeInOut(duration: 0.2)
        } else {
            return .spring(response: 0.5, dampingFraction: 0.8)
        }
    }
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 8) {
                    ForEach(0..<adaptiveSkeletonCount, id: \.self) { index in
                        LiquidSkeletonView(style: skeletonStyle)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                removal: .opacity
                            ))
                            .animation(adaptiveAnimation.delay(Double(index) * 0.05), value: isLoading)
                    }
                }
            } else {
                content()
            }
        }
        .animation(adaptiveAnimation, value: isLoading)
    }
}

// MARK: - Usage Extensions

extension View {
    func skeletonLoading(
        _ isLoading: Bool,
        skeleton: LiquidSkeletonView.SkeletonStyle,
        count: Int = 1
    ) -> some View {
        SmartLoadingState(isLoading: isLoading, skeleton: skeleton, count: count) {
            self
        }
    }
}

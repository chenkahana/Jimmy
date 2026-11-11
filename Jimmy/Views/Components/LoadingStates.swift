import SwiftUI
import UIKit

// MARK: - Enhanced Loading States System

/// Comprehensive loading state management for better user experience
/// Provides skeleton screens, progress indicators, and contextual feedback
struct LoadingStateHelper {
    static let shared = LoadingStateHelper()
    
    private init() {}
    
    // MARK: - Loading State Types
    
    enum LoadingType {
        case initial        // First time loading
        case refresh        // Pull to refresh
        case pagination     // Loading more content
        case background     // Background updates
        case search         // Search operations
        case upload         // Upload operations
        case download       // Download operations
        
        var showsProgress: Bool {
            switch self {
            case .upload, .download: return true
            default: return false
            }
        }
        
        var animationDuration: Double {
            switch self {
            case .initial: return 0.5
            case .refresh: return 0.3
            case .pagination: return 0.2
            default: return 0.3
            }
        }
    }
}

// MARK: - Enhanced Loading Indicators

/// Contextual loading spinner with message and progress support
struct ContextualLoadingIndicator: View {
    let type: LoadingStateCoordinator.LoadingOperation.LoadingType
    let message: String
    let progress: Double?
    let showCancel: Bool
    let onCancel: (() -> Void)?
    
    @State private var isAnimating = false
    
    init(
        type: LoadingStateCoordinator.LoadingOperation.LoadingType = .contentLoading,
        message: String,
        progress: Double? = nil,
        showCancel: Bool = false,
        onCancel: (() -> Void)? = nil
    ) {
        self.type = type
        self.message = message
        self.progress = progress
        self.showCancel = showCancel
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Loading animation
            ZStack {
                if let progress = progress {
                    // Progress ring for operations with known progress
                    ProgressRing(
                        progress: progress,
                        size: 60,
                        lineWidth: 6,
                        color: .blue
                    )
                } else {
                    // Animated spinner for indeterminate operations
                    AnimatedLoadingSpinner(
                        size: 60,
                        color: .blue,
                        style: spinnerStyle
                    )
                }
            }
            
            // Message and details
            VStack(spacing: 8) {
                Text(message)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if let progress = progress {
                    Text("\(Int(progress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Cancel button if needed
            if showCancel, let onCancel = onCancel {
                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .scaleEffect(isAnimating ? 1.0 : 0.9)
        .opacity(isAnimating ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
    
    private var spinnerStyle: AnimatedLoadingSpinner.Style {
        switch type {
        case .appInitialization, .dataRefresh: return .dots
        case .contentLoading: return .minimal
        case .networkRequest: return .pulse
        case .imageLoading, .fileOperation: return .ring
        default: return .dots
        }
    }
}

/// Advanced animated loading spinner with multiple styles
struct AnimatedLoadingSpinner: View {
    let size: CGFloat
    let color: Color
    let style: Style
    
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    enum Style {
        case dots       // Bouncing dots
        case ring       // Rotating ring
        case pulse      // Pulsing circle
        case minimal    // Simple spinner
        case wave       // Wave animation
    }
    
    init(size: CGFloat = 40, color: Color = .blue, style: Style = .dots) {
        self.size = size
        self.color = color
        self.style = style
    }
    
    var body: some View {
        Group {
            switch style {
            case .dots:
                dotsAnimation
            case .ring:
                ringAnimation
            case .pulse:
                pulseAnimation
            case .minimal:
                minimalAnimation
            case .wave:
                waveAnimation
            }
        }
        .frame(width: size, height: size)
    }
    
    private var dotsAnimation: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .scaleEffect(scale)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: scale
                    )
            }
        }
        .onAppear {
            scale = 0.5
        }
    }
    
    private var ringAnimation: some View {
        Circle()
            .trim(from: 0.2, to: 1.0)
            .stroke(
                AngularGradient(
                    colors: [color.opacity(0.1), color],
                    center: .center
                ),
                style: StrokeStyle(
                    lineWidth: size * 0.1,
                    lineCap: .round
                )
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
    
    private var pulseAnimation: some View {
        Circle()
            .fill(color.opacity(opacity))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.2
                    opacity = 0.3
                }
            }
    }
    
    private var minimalAnimation: some View {
        Circle()
            .trim(from: 0.0, to: 0.7)
            .stroke(color, lineWidth: size * 0.08)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
    
    private var waveAnimation: some View {
        HStack(spacing: size * 0.1) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.05)
                    .fill(color)
                    .frame(width: size * 0.1, height: size * 0.4)
                    .scaleEffect(y: scale)
                    .animation(
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: scale
                    )
            }
        }
        .onAppear {
            scale = 0.3
        }
    }
}

/// Progress ring with smooth animations
struct ProgressRing: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    @State private var animatedProgress: Double = 0
    
    init(
        progress: Double,
        size: CGFloat = 60,
        lineWidth: CGFloat = 6,
        color: Color = .blue
    ) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.7), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
            
            // Progress text
            Text("\(Int(animatedProgress * 100))%")
                .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
        .onChange(of: progress) { _, newProgress in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = newProgress
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Enhanced Skeleton Screens

/// Intelligent skeleton screen that adapts to content type
struct AdaptiveSkeletonScreen: View {
    let contentType: ContentType
    let itemCount: Int
    let animated: Bool
    
    enum ContentType {
        case podcastGrid
        case episodeList
        case searchResults
        case podcastDetail
        case playerView
        
        var itemHeight: CGFloat {
            switch self {
            case .podcastGrid: return 160
            case .episodeList: return 80
            case .searchResults: return 70
            case .podcastDetail: return 200
            case .playerView: return 300
            }
        }
    }
    
    init(
        contentType: ContentType,
        itemCount: Int = 6,
        animated: Bool = true
    ) {
        self.contentType = contentType
        self.itemCount = itemCount
        self.animated = animated
    }
    
    var body: some View {
        Group {
            switch contentType {
            case .podcastGrid:
                podcastGridSkeleton
            case .episodeList:
                episodeListSkeleton
            case .searchResults:
                searchResultsSkeleton
            case .podcastDetail:
                podcastDetailSkeleton
            case .playerView:
                playerViewSkeleton
            }
        }
    }
    
    private var podcastGridSkeleton: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 16
        ) {
            ForEach(0..<itemCount, id: \.self) { index in
                VStack(spacing: 8) {
                    SkeletonShape(width: 120, height: 120, cornerRadius: 12)
                    SkeletonShape(width: 100, height: 12, cornerRadius: 2)
                    SkeletonShape(width: 80, height: 10, cornerRadius: 2)
                }
                .shimmerEffect(animated: animated, delay: Double(index) * 0.1)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var episodeListSkeleton: some View {
        LazyVStack(spacing: 12) {
            ForEach(0..<itemCount, id: \.self) { index in
                HStack(spacing: 12) {
                    SkeletonShape(width: 60, height: 60, cornerRadius: 8)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonShape(width: 200, height: 16, cornerRadius: 2)
                        SkeletonShape(width: 150, height: 12, cornerRadius: 2)
                        SkeletonShape(width: 100, height: 8, cornerRadius: 4)
                    }
                    
                    Spacer()
                    
                    SkeletonShape(width: 30, height: 30, cornerRadius: 15)
                }
                .padding(.horizontal, 16)
                .shimmerEffect(animated: animated, delay: Double(index) * 0.05)
            }
        }
    }
    
    private var searchResultsSkeleton: some View {
        LazyVStack(spacing: 8) {
            ForEach(0..<itemCount, id: \.self) { index in
                HStack(spacing: 12) {
                    SkeletonShape(width: 50, height: 50, cornerRadius: 6)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonShape(width: 180, height: 14, cornerRadius: 2)
                        SkeletonShape(width: 120, height: 10, cornerRadius: 2)
                    }
                    
                    Spacer()
                    
                    SkeletonShape(width: 60, height: 20, cornerRadius: 10)
                }
                .padding(.horizontal, 16)
                .shimmerEffect(animated: animated, delay: Double(index) * 0.03)
            }
        }
    }
    
    private var podcastDetailSkeleton: some View {
        VStack(spacing: 20) {
            // Header skeleton
            VStack(spacing: 12) {
                SkeletonShape(width: 200, height: 200, cornerRadius: 20)
                SkeletonShape(width: 250, height: 20, cornerRadius: 2)
                SkeletonShape(width: 180, height: 16, cornerRadius: 2)
            }
            
            // Action buttons skeleton
            HStack(spacing: 12) {
                SkeletonShape(width: 100, height: 40, cornerRadius: 20)
                SkeletonShape(width: 80, height: 40, cornerRadius: 20)
            }
            
            // Episodes list skeleton
            episodeListSkeleton
        }
        .shimmerEffect(animated: animated)
    }
    
    private var playerViewSkeleton: some View {
        VStack(spacing: 24) {
            // Artwork skeleton
            SkeletonShape(width: 280, height: 280, cornerRadius: 24)
            
            // Title and artist skeleton
            VStack(spacing: 8) {
                SkeletonShape(width: 300, height: 20, cornerRadius: 2)
                SkeletonShape(width: 200, height: 16, cornerRadius: 2)
            }
            
            // Progress bar skeleton
            SkeletonShape(width: 320, height: 4, cornerRadius: 2)
            
            // Controls skeleton
            HStack(spacing: 40) {
                SkeletonShape(width: 40, height: 40, cornerRadius: 20)
                SkeletonShape(width: 60, height: 60, cornerRadius: 30)
                SkeletonShape(width: 40, height: 40, cornerRadius: 20)
            }
        }
        .shimmerEffect(animated: animated)
    }
}

/// Basic skeleton shape with customizable dimensions
struct SkeletonShape: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
    }
}

/// Shimmer effect modifier for skeleton screens
struct ShimmerEffect: ViewModifier {
    let animated: Bool
    let delay: Double
    
    @State private var isShimmering = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: animated ? [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.clear
                            ] : [Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: isShimmering ? 1 : 0, y: 1, anchor: .leading)
                    .animation(
                        animated ? .linear(duration: 1.5).repeatForever(autoreverses: false).delay(delay) : .none,
                        value: isShimmering
                    )
            )
            .onAppear {
                if animated {
                    isShimmering = true
                }
            }
    }
}

extension View {
    func shimmerEffect(animated: Bool = true, delay: Double = 0) -> some View {
        modifier(ShimmerEffect(animated: animated, delay: delay))
    }
}

// MARK: - Error States and Feedback

/// Enhanced error state with recovery options
struct ErrorStateView: View {
    let error: ErrorType
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    enum ErrorType {
        case network
        case parsing
        case notFound
        case unauthorized
        case serverError
        case unknown(String)
        
        var icon: String {
            switch self {
            case .network: return "wifi.exclamationmark"
            case .parsing: return "doc.text.fill"
            case .notFound: return "magnifyingglass"
            case .unauthorized: return "lock.fill"
            case .serverError: return "server.rack"
            case .unknown: return "exclamationmark.triangle.fill"
            }
        }
        
        var title: String {
            switch self {
            case .network: return "Connection Error"
            case .parsing: return "Data Error"
            case .notFound: return "Not Found"
            case .unauthorized: return "Access Denied"
            case .serverError: return "Server Error"
            case .unknown: return "Something Went Wrong"
            }
        }
        
        var message: String {
            switch self {
            case .network: return "Please check your internet connection and try again."
            case .parsing: return "There was a problem processing the data."
            case .notFound: return "The requested content could not be found."
            case .unauthorized: return "You don't have permission to access this content."
            case .serverError: return "The server is experiencing issues. Please try again later."
            case .unknown(let message): return message
            }
        }
        
        var color: Color {
            switch self {
            case .network: return .orange
            case .parsing: return .red
            case .notFound: return .gray
            case .unauthorized: return .red
            case .serverError: return .red
            case .unknown: return .yellow
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: error.icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(error.color)
            
            // Error content
            VStack(spacing: 12) {
                Text(error.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(error.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(error.color)
                        .cornerRadius(12)
                    }
                }
                
                if let onDismiss = onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - Success Feedback

/// Success feedback with customizable styling
struct SuccessFeedback: View {
    let message: String
    let icon: String
    let duration: TimeInterval
    let onDismiss: (() -> Void)?
    
    @State private var isVisible = false
    
    init(
        message: String,
        icon: String = "checkmark.circle.fill",
        duration: TimeInterval = 3.0,
        onDismiss: (() -> Void)? = nil
    ) {
        self.message = message
        self.icon = icon
        self.duration = duration
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)
            
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isVisible = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isVisible = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss?()
                }
            }
        }
    }
}

// MARK: - Loading State View Modifiers

struct LoadingStateModifier<LoadingContent: View>: ViewModifier {
    let isLoading: Bool
    let loadingContent: () -> LoadingContent
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isLoading ? 0.3 : 1.0)
                .disabled(isLoading)
            
            if isLoading {
                loadingContent()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
    }
}

extension View {
    /// Apply loading state overlay
    func loadingState<LoadingContent: View>(
        isLoading: Bool,
        @ViewBuilder loadingContent: @escaping () -> LoadingContent
    ) -> some View {
        modifier(LoadingStateModifier(isLoading: isLoading, loadingContent: loadingContent))
    }
    
    /// Apply simple loading state with spinner
    func loadingState(isLoading: Bool, message: String = "Loading...") -> some View {
        loadingState(isLoading: isLoading) {
            ContextualLoadingIndicator(
                type: .contentLoading,
                message: message
            )
        }
    }
}
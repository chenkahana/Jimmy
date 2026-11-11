import SwiftUI
import UIKit

/// Utility for optimizing scroll performance across the app
@MainActor
class ScrollPerformanceOptimizer: ObservableObject {
    static let shared = ScrollPerformanceOptimizer()
    
    // MARK: - Performance Tracking
    @Published private(set) var currentScrollFPS: Double = 0
    @Published private(set) var isScrolling: Bool = false
    @Published private(set) var scrollPerformanceGrade: PerformanceGrade = .excellent
    
    private var scrollDisplayLink: CADisplayLink?
    private var lastScrollTime = CACurrentMediaTime()
    private var frameCount = 0
    private let performanceMonitor = PerformanceMonitor.shared
    
    enum PerformanceGrade: String {
        case excellent = "excellent"  // >100fps
        case good = "good"       // 60-100fps
        case fair = "fair"       // 30-60fps
        case poor = "poor"       // <30fps
        
        var color: Color {
            switch self {
            case .excellent: return .green
            case .good: return .blue
            case .fair: return .orange
            case .poor: return .red
            }
        }
    }
    
    private init() {}
    
    // MARK: - Scroll Performance Monitoring
    
    func startScrollMonitoring() {
        guard scrollDisplayLink == nil else { return }
        
        isScrolling = true
        frameCount = 0
        lastScrollTime = CACurrentMediaTime()
        
        scrollDisplayLink = CADisplayLink(target: self, selector: #selector(scrollFrameCallback))
        scrollDisplayLink?.preferredFramesPerSecond = 0 // Use maximum available
        
        if #available(iOS 15.0, *) {
            scrollDisplayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: 120,
                preferred: 120
            )
        }
        
        scrollDisplayLink?.add(to: .main, forMode: .common)
    }
    
    func stopScrollMonitoring() {
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        isScrolling = false
        
        // Log final scroll performance
        if frameCount > 0 {
            performanceMonitor.logCustomEvent(
                name: "ScrollPerformance",
                duration: CACurrentMediaTime() - lastScrollTime,
                metadata: [
                    "finalFPS": currentScrollFPS,
                    "frameCount": frameCount,
                    "performanceGrade": scrollPerformanceGrade.rawValue
                ]
            )
        }
    }
    
    @objc private func scrollFrameCallback() {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastScrollTime
        
        if deltaTime > 0 {
            currentScrollFPS = 1.0 / deltaTime
            frameCount += 1
            
            // Update performance grade
            updatePerformanceGrade()
        }
        
        lastScrollTime = currentTime
    }
    
    private func updatePerformanceGrade() {
        switch currentScrollFPS {
        case 100...:
            scrollPerformanceGrade = .excellent
        case 60..<100:
            scrollPerformanceGrade = .good
        case 30..<60:
            scrollPerformanceGrade = .fair
        default:
            scrollPerformanceGrade = .poor
        }
    }
    
    // MARK: - Scroll Optimization Utilities
    
    /// Optimizes scroll view for better performance
    static func optimizeScrollView<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content()
            }
            .drawingGroup() // Composite layers for better performance
        }
        .scrollIndicators(.hidden) // Reduce rendering overhead
        .clipped() // Prevent overdraw
    }
    
    /// Creates a performance-optimized LazyVGrid
    static func optimizedLazyVGrid<Content: View>(
        columns: [GridItem],
        spacing: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content()
        }
        .compositingGroup() // Reduce layer count
    }
    
    /// Creates a performance-optimized LazyVStack
    static func optimizedLazyVStack<Content: View>(
        spacing: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        LazyVStack(spacing: spacing) {
            content()
        }
        .compositingGroup() // Reduce layer count
    }
}

// MARK: - View Modifiers

struct ScrollPerformanceMonitored: ViewModifier {
    @StateObject private var optimizer = ScrollPerformanceOptimizer.shared
    
    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { oldPhase, newPhase in
                switch newPhase {
                case .idle:
                    optimizer.stopScrollMonitoring()
                case .tracking, .interacting, .decelerating, .animating:
                    optimizer.startScrollMonitoring()
                @unknown default:
                    break
                }
            }
    }
}

struct OptimizedScrolling: ViewModifier {
    let enablePerformanceMode: Bool
    
    func body(content: Content) -> some View {
        if enablePerformanceMode {
            content
                .drawingGroup() // Composite for better performance
                .clipped() // Prevent overdraw
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Monitors scroll performance and provides metrics
    func scrollPerformanceMonitored() -> some View {
        modifier(ScrollPerformanceMonitored())
    }
    
    /// Applies scroll performance optimizations
    func optimizedScrolling(enablePerformanceMode: Bool = true) -> some View {
        modifier(OptimizedScrolling(enablePerformanceMode: enablePerformanceMode))
    }
    
    /// Comprehensive scroll optimization
    func scrollOptimized() -> some View {
        self
            .scrollPerformanceMonitored()
            .optimizedScrolling()
    }
}

// MARK: - Scroll Performance Debug View

struct ScrollPerformanceDebugOverlay: View {
    @StateObject private var optimizer = ScrollPerformanceOptimizer.shared
    
    var body: some View {
        VStack {
            Spacer()
            
            if optimizer.isScrolling {
                HStack {
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("FPS: \(String(format: "%.1f", optimizer.currentScrollFPS))")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(optimizer.scrollPerformanceGrade.color)
                        
                        Text(optimizer.scrollPerformanceGrade.rawValue.uppercased())
                            .font(.caption2.bold())
                            .foregroundColor(optimizer.scrollPerformanceGrade.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(optimizer.scrollPerformanceGrade.color.opacity(0.5), lineWidth: 1)
                            )
                    )
                    .padding(.trailing, 16)
                }
            }
        }
        .allowsHitTesting(false)
    }
}


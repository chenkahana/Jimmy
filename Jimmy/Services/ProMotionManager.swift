import UIKit
import SwiftUI

/// Manages ProMotion/120Hz display support and optimization
@MainActor
class ProMotionManager: ObservableObject {
    static let shared = ProMotionManager()
    
    // MARK: - Published Properties
    @Published private(set) var isProMotionAvailable: Bool = false
    @Published private(set) var currentMaxFrameRate: Int = 60
    @Published private(set) var isLowPowerModeActive: Bool = false
    @Published private(set) var effectiveMaxFrameRate: Int = 60
    
    // MARK: - Private Properties
    private var displayLink: CADisplayLink?
    private var frameRateObserver: NSObjectProtocol?
    
    private init() {
        setupProMotionDetection()
        setupLowPowerModeObserver()
        startFrameRateMonitoring()
    }
    
    deinit {
        Task { @MainActor in
            stopFrameRateMonitoring()
        }
        if let observer = frameRateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - ProMotion Detection
    
    private func setupProMotionDetection() {
        let screen = UIScreen.main
        currentMaxFrameRate = screen.maximumFramesPerSecond
        isProMotionAvailable = currentMaxFrameRate > 60
        updateEffectiveFrameRate()
        
        print("🖥️ ProMotion Detection:")
        print("   - Max Frame Rate: \(currentMaxFrameRate)Hz")
        print("   - ProMotion Available: \(isProMotionAvailable)")
    }
    
    private func setupLowPowerModeObserver() {
        frameRateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateLowPowerModeStatus()
            }
        }
        updateLowPowerModeStatus()
    }
    
    private func updateLowPowerModeStatus() {
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        updateEffectiveFrameRate()
        
        print("🔋 Low Power Mode: \(isLowPowerModeActive ? "ON" : "OFF")")
        print("   - Effective Frame Rate: \(effectiveMaxFrameRate)Hz")
    }
    
    private func updateEffectiveFrameRate() {
        // In Low Power Mode, iOS caps frame rate to 60Hz even on ProMotion displays
        if isLowPowerModeActive {
            effectiveMaxFrameRate = 60
        } else {
            effectiveMaxFrameRate = currentMaxFrameRate
        }
    }
    
    // MARK: - Frame Rate Monitoring
    
    private func startFrameRateMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback))
        displayLink?.preferredFramesPerSecond = 0 // Use maximum available
        
        // Set preferred frame rate range for iOS 15+
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: Float(currentMaxFrameRate),
                preferred: Float(currentMaxFrameRate)
            )
        }
        
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopFrameRateMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkCallback() {
        // This runs at the current display refresh rate
        // We can use this for frame rate monitoring if needed
    }
    
    // MARK: - Public API
    
    /// Returns the optimal animation duration for the current display
    func optimizedAnimationDuration(_ baseDuration: TimeInterval) -> TimeInterval {
        // Shorter durations for higher frame rates to maintain smoothness
        let frameRateMultiplier = Double(effectiveMaxFrameRate) / 60.0
        return baseDuration / frameRateMultiplier
    }
    
    /// Returns the optimal spring response for the current display
    func optimizedSpringResponse(_ baseResponse: Double) -> Double {
        // Faster spring response for higher frame rates
        let frameRateMultiplier = Double(effectiveMaxFrameRate) / 60.0
        return baseResponse / frameRateMultiplier
    }
    
    /// Creates an optimized CADisplayLink for custom animations
    func createOptimizedDisplayLink(target: Any, selector: Selector) -> CADisplayLink {
        let link = CADisplayLink(target: target, selector: selector)
        link.preferredFramesPerSecond = 0 // Use maximum available
        
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60,
                maximum: Float(effectiveMaxFrameRate),
                preferred: Float(effectiveMaxFrameRate)
            )
        }
        
        return link
    }
    
    /// Returns optimized animation settings for SwiftUI
    func optimizedAnimation(_ animation: Animation) -> Animation {
        // For now, return the original animation
        // This method can be enhanced in the future for specific animation optimizations
        return animation
    }
    
    /// Debug information about current display state
    var debugInfo: String {
        """
        ProMotion Debug Info:
        - Device Max Frame Rate: \(currentMaxFrameRate)Hz
        - ProMotion Available: \(isProMotionAvailable)
        - Low Power Mode: \(isLowPowerModeActive)
        - Effective Frame Rate: \(effectiveMaxFrameRate)Hz
        - Display Link Active: \(displayLink != nil)
        """
    }
}

// MARK: - SwiftUI Extensions

extension Animation {
    /// Creates a ProMotion-optimized spring animation
    @MainActor
    static func proMotionSpring(
        response: Double = 0.25,
        dampingFraction: Double = 0.85,
        blendDuration: Double = 0
    ) -> Animation {
        let manager = ProMotionManager.shared
        return .spring(
            response: manager.optimizedSpringResponse(response),
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }
    
    /// Creates a ProMotion-optimized easeInOut animation
    @MainActor
    static func proMotionEaseInOut(duration: Double = 0.25) -> Animation {
        let manager = ProMotionManager.shared
        return .easeInOut(duration: manager.optimizedAnimationDuration(duration))
    }
    
    /// Creates a ProMotion-optimized linear animation
    @MainActor
    static func proMotionLinear(duration: Double = 1.0) -> Animation {
        let manager = ProMotionManager.shared
        return .linear(duration: manager.optimizedAnimationDuration(duration))
    }
}

// MARK: - View Modifier

struct ProMotionOptimized: ViewModifier {
    @StateObject private var proMotionManager = ProMotionManager.shared
    
    func body(content: Content) -> some View {
        content
            .environment(\.proMotionManager, proMotionManager)
    }
}

extension View {
    /// Applies ProMotion optimization to the view
    func proMotionOptimized() -> some View {
        modifier(ProMotionOptimized())
    }
}

// MARK: - Environment Key

private struct ProMotionManagerKey: EnvironmentKey {
    @MainActor
    static let defaultValue = ProMotionManager.shared
}

extension EnvironmentValues {
    var proMotionManager: ProMotionManager {
        get { self[ProMotionManagerKey.self] }
        set { self[ProMotionManagerKey.self] = newValue }
    }
} 
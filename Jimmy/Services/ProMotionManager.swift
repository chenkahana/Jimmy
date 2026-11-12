import UIKit
import SwiftUI

/// Scales animation durations/spring responses to the display's refresh rate, so motion looks
/// equally smooth on 60Hz and ProMotion (120Hz) screens, and backs off to 60Hz in Low Power Mode.
@MainActor
final class ProMotionManager {
    static let shared = ProMotionManager()

    private let currentMaxFrameRate: Int
    private var isLowPowerModeActive: Bool
    private var frameRateObserver: NSObjectProtocol?

    private var effectiveMaxFrameRate: Int {
        isLowPowerModeActive ? 60 : currentMaxFrameRate
    }

    private init() {
        currentMaxFrameRate = UIScreen.main.maximumFramesPerSecond
        isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled

        frameRateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    isolated deinit {
        if let observer = frameRateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Returns the optimal animation duration for the current display
    func optimizedAnimationDuration(_ baseDuration: TimeInterval) -> TimeInterval {
        let frameRateMultiplier = Double(effectiveMaxFrameRate) / 60.0
        return baseDuration / frameRateMultiplier
    }

    /// Returns the optimal spring response for the current display
    func optimizedSpringResponse(_ baseResponse: Double) -> Double {
        let frameRateMultiplier = Double(effectiveMaxFrameRate) / 60.0
        return baseResponse / frameRateMultiplier
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
}

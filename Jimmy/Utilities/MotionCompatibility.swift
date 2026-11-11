import SwiftUI
import UIKit

// MARK: - Motion Compatibility Layer
// Provides Motion-like APIs using native SwiftUI and UIKit

/// Motion haptic feedback utilities
enum Motion {
    static func lightHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    static func mediumHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    static func rigidHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .rigid)
        impactFeedback.impactOccurred()
    }
    
    static func selectionHaptic() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
}

// MARK: - Animation Extensions
extension Animation {
    /// Motion-style spring animation
    static var motion: Animation {
        .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0)
    }
    
    /// Gentle motion animation
    static var motionGentle: Animation {
        .spring(response: 0.6, dampingFraction: 0.9, blendDuration: 0)
    }
    
    /// Micro motion animation for subtle interactions
    static var motionMicro: Animation {
        .spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0)
    }
    
    /// Transition motion animation
    static var motionTransition: Animation {
        .spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)
    }
}

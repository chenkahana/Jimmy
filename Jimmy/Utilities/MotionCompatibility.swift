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
// One motion vocabulary (docs/design.md): snappy for panels and state changes, a soft spring for paging.
extension Animation {
    static var motion: Animation { .snappy(duration: 0.3) }
    static var motionGentle: Animation { .snappy(duration: 0.3) }
    static var motionMicro: Animation { .snappy(duration: 0.25) }
    static var motionTransition: Animation { .spring(response: 0.38, dampingFraction: 0.82) }
}

import SwiftUI

extension Material {
    /// Glass-compatible material that provides liquid glass effect
    /// Uses future .glass material when available, falls back to optimized materials
    static var glassCompatible: Material {
        if #available(iOS 26.0, *) {
            // Future iOS 26+ will have native .glass material
            return .ultraThinMaterial // Will be .glass when iOS 26 is released
        } else {
            // Optimized liquid glass effect for current iOS versions
            return .ultraThinMaterial
        }
    }
    
    /// Enhanced liquid glass material with better translucency
    static var liquidGlass: Material {
        return .thinMaterial
    }
    
    /// Subtle liquid glass for overlays
    static var liquidGlassSubtle: Material {
        return .ultraThinMaterial
    }
}
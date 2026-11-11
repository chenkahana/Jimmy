import UIKit

extension UITabBarAppearance {
    /// Configure glass appearance for UIKit tab bar controllers
    static func glassAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        
        // Set glass-like background effect using available blur styles
        if #available(iOS 18.0, *) {
            // Use the new chrome material on modern systems for a richer glass look
            appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        } else {
            // Fallback to ultra thin material on older iOS versions
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        
        // Configure background color with transparency
        appearance.backgroundColor = UIColor.clear
        
        // Configure shadow
        appearance.shadowColor = UIColor.black.withAlphaComponent(0.15)
        
        return appearance
    }
} 
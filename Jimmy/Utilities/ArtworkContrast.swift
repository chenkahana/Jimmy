import SwiftUI

/// A color sampled from show artwork, checked for text legibility with WCAG 2 contrast arithmetic.
///
/// Text on the color is black or white, whichever reads better, and must reach 4.5:1. Near-white and
/// near-black artwork tints nothing: `usable` is `nil` and the caller falls back to a system background.
nonisolated struct ArtworkContrast: Equatable, Sendable {
    /// sRGB components, 0...1.
    let red: Double
    let green: Double
    let blue: Double

    static let black = ArtworkContrast(red: 0, green: 0, blue: 0)
    static let white = ArtworkContrast(red: 1, green: 1, blue: 1)
    static let minimumTextContrast = 4.5
    /// Below this luminance the color reads as black, above the upper bound as white.
    static let usableLuminance = 0.02...0.7

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(_ color: Color.Resolved) {
        self.init(red: Double(color.red), green: Double(color.green), blue: Double(color.blue))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21.
    func contrast(with other: ArtworkContrast) -> Double {
        let lighter = max(luminance, other.luminance), darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Black or white, whichever has more contrast on this color.
    var text: ArtworkContrast { contrast(with: .black) >= contrast(with: .white) ? .black : .white }

    /// This color, when it is neither near-white nor near-black and its text passes 4.5:1.
    var usable: ArtworkContrast? {
        Self.usableLuminance.contains(luminance) && contrast(with: text) >= Self.minimumTextContrast ? self : nil
    }

    /// The appearance whose controls stay legible on this color.
    var colorScheme: ColorScheme { text == .black ? .light : .dark }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

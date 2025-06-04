import SwiftUI

enum ColorPalette {
    /// Vibrant gradient color pairs used throughout the Discover page
    static let gradientPairs: [(Color, Color)] = [
        (.pink, .orange),
        (.purple, .blue),
        (.green, .mint),
        (.yellow, .red),
        (.indigo, .purple),
        (.teal, .cyan),
        (.orange, .red),
        (.pink, .purple),
        (.cyan, .indigo),
        (.mint, .teal),
        (.brown, .orange),
        (.red, .purple)
    ]

    /// Returns a gradient pair for the given index, wrapping around the palette
    static func pair(for index: Int) -> (Color, Color) {
        gradientPairs[index % gradientPairs.count]
    }
}

//
//  NowPlayingNamespace.swift
//  Jimmy
//
//  Shared namespace manager for coordinating mini player → full screen transitions
//

import SwiftUI

/// Environment key for passing the now playing namespace
struct NowPlayingNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var nowPlayingNamespace: Namespace.ID? {
        get { self[NowPlayingNamespaceKey.self] }
        set { self[NowPlayingNamespaceKey.self] = newValue }
    }
}

/// Identifiers for matched geometry effects
enum NowPlayingGeometryID {
    static let artwork = "nowPlayingArtwork"
    static let title = "nowPlayingTitle"
    static let subtitle = "nowPlayingSubtitle"
    static let progress = "nowPlayingProgress"
}

// MARK: - View Extension for Conditional Modifiers

extension View {
    /// Conditionally applies a transformation to a view
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}


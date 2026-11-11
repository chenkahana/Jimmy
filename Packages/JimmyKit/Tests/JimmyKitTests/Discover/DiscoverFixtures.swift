import Foundation

/// Shared helpers for locating the JSON fixture files under `Tests/Fixtures/Discover` at
/// the repo root — same approach as `FeedFixtures`, so loose JSON doesn't need declaring
/// as an SPM package resource.
enum DiscoverFixtures {
    /// `Tests/Fixtures/Discover` at the repo root, resolved relative to this source file's
    /// own location so it works regardless of the current working directory.
    static let directory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DiscoverFixtures.swift -> Discover/
            .deletingLastPathComponent() // Discover/ -> JimmyKitTests/
            .deletingLastPathComponent() // JimmyKitTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> JimmyKit/
            .deletingLastPathComponent() // JimmyKit/ -> Packages/
            .deletingLastPathComponent() // Packages/ -> repo root
            .appendingPathComponent("Tests/Fixtures/Discover", isDirectory: true)
    }()

    static func data(_ filename: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(filename))
    }
}

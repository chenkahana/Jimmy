// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "JimmyKit",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v26)],
    products: [.library(name: "JimmyKit", targets: ["JimmyKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    ],
    targets: [
        .target(
            name: "JimmyKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "JimmyKitTests",
            dependencies: ["JimmyKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JimmyUtilities",
    platforms: [
        .macOS(.v10_15), .iOS(.v13)
    ],
    products: [
        .library(name: "JimmyUtilities", targets: ["JimmyUtilities"])
    ],
    targets: [
        .target(
            name: "JimmyUtilities",
            path: "Jimmy",
            sources: [
                "Utilities/FileStorage.swift",
                "Utilities/SpotifyListParser.swift",
                "Utilities/UserDataService.swift",
                "Utilities/AppleBulkImportParser.swift",
                "Utilities/GoogleTakeoutParser.swift",
                "Utilities/OPMLParser.swift",
                "Utilities/StringExtensions.swift",
                "Models/Podcast.swift"
            ]
        ),
        .testTarget(
            name: "JimmyTests",
            dependencies: ["JimmyUtilities"]
        )
    ]
)

// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaShoot",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VideoSyncCore", targets: ["VideoSyncCore"]),
        .library(name: "ReaShootKit", targets: ["ReaShootKit"]),
        .executable(name: "video-sync-mac", targets: ["video-sync-mac"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VideoSyncCore"
        ),
        .target(
            name: "ReaShootKit",
            dependencies: [
                "VideoSyncCore"
            ]
        ),
        .executableTarget(
            name: "video-sync-mac",
            dependencies: ["VideoSyncCore"]
        ),
        .testTarget(
            name: "VideoSyncCoreTests",
            dependencies: ["VideoSyncCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

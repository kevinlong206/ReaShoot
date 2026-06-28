// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaperVideoSyncHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "video-sync-mac", targets: ["video-sync-mac"])
    ],
    targets: [
        .target(name: "VideoSyncCore"),
        .executableTarget(
            name: "video-sync-mac",
            dependencies: ["VideoSyncCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

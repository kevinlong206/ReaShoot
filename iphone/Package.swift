// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "iPhoneReaperVideoSync",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VideoSyncCore", targets: ["VideoSyncCore"]),
        .library(name: "iPhoneVideoSyncKit", targets: ["iPhoneVideoSyncKit"]),
        .executable(name: "video-sync-mac", targets: ["video-sync-mac"])
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", branch: "main")
    ],
    targets: [
        .target(
            name: "VideoSyncCore"
        ),
        .target(
            name: "iPhoneVideoSyncKit",
            dependencies: [
                "VideoSyncCore",
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework")
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

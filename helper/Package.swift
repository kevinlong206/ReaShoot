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
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", branch: "main")
    ],
    targets: [
        .target(name: "VideoSyncCore"),
        .target(
            name: "WebRTCDependency",
            dependencies: [
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework")
            ]
        ),
        .executableTarget(
            name: "video-sync-mac",
            dependencies: ["VideoSyncCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

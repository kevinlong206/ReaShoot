// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaShoot",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReaShootCore", targets: ["ReaShootCore"]),
        .library(name: "ReaShootKit", targets: ["ReaShootKit"]),
        .executable(name: "reashoot-mac", targets: ["reashoot-mac"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ReaShootCore"
        ),
        .target(
            name: "ReaShootKit",
            dependencies: [
                "ReaShootCore"
            ]
        ),
        .executableTarget(
            name: "reashoot-mac",
            dependencies: ["ReaShootCore"]
        ),
        .testTarget(
            name: "ReaShootCoreTests",
            dependencies: ["ReaShootCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

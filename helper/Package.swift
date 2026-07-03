// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaShootHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "reashoot-mac", targets: ["reashoot-mac"])
    ],
    dependencies: [],
    targets: [
        .target(name: "ReaShootCore"),
        .executableTarget(
            name: "reashoot-mac",
            dependencies: ["ReaShootCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)

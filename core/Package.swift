// swift-tools-version: 6.0

import PackageDescription

// MooringsCore is the pure logic both apps share: geometry, snapping, actions and anchors.
let package = Package(
    name: "MooringsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MooringsCore", targets: ["MooringsCore"]),
    ],
    targets: [
        .target(name: "MooringsCore"),
        .testTarget(
            name: "MooringsCoreTests",
            dependencies: ["MooringsCore"]
        ),
    ]
)

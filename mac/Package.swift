// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Moorings",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MooringsCore"),
        .executableTarget(
            name: "Moorings",
            dependencies: ["MooringsCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "MooringsCoreTests",
            dependencies: ["MooringsCore"]
        ),
    ]
)

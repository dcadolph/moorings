// swift-tools-version: 6.0

import PackageDescription

// MooringsCore is the pure logic both apps share, MooringsEngine the orchestration both run on, and
// MooringsTesting the fakes and contracts every test target uses.
let package = Package(
    name: "MooringsCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MooringsCore", targets: ["MooringsCore"]),
        .library(name: "MooringsEngine", targets: ["MooringsEngine"]),
        .library(name: "MooringsTesting", targets: ["MooringsTesting"]),
    ],
    targets: [
        .target(name: "MooringsCore"),
        // MooringsEngine holds the platform protocols and the orchestrators written once against them.
        .target(name: "MooringsEngine", dependencies: ["MooringsCore"]),
        // MooringsTesting holds a fake for every protocol and the contract suites, for every test target.
        .target(name: "MooringsTesting", dependencies: ["MooringsCore", "MooringsEngine"]),
        .testTarget(
            name: "MooringsCoreTests",
            dependencies: ["MooringsCore"]
        ),
        .testTarget(
            name: "MooringsEngineTests",
            dependencies: ["MooringsCore", "MooringsEngine", "MooringsTesting"]
        ),
    ]
)

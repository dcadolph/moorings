// swift-tools-version: 6.0

import PackageDescription

var targets: [Target] = []

// The app layer is AppKit, so other platforms build nothing here.
#if os(macOS)
targets.append(
    .executableTarget(
        name: "Moorings",
        dependencies: [.product(name: "MooringsCore", package: "core")],
        exclude: ["Info.plist"]
    )
)
#endif

let package = Package(
    name: "Moorings",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../core")],
    targets: targets
)

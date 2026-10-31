// swift-tools-version: 6.0

import PackageDescription

var targets: [Target] = []

// The app layer is AppKit, so other platforms build nothing here.
#if os(macOS)
    targets.append(
        .executableTarget(
            name: "Moorings",
            dependencies: [
                .product(name: "MooringsCore", package: "core"),
                .product(name: "MooringsEngine", package: "core"),
            ],
            exclude: ["Info.plist"]
        )
    )
    // MooringsProbe is the plain window app the selftest, the Mac contracts and the bench move.
    // make probe bundles it as .build/MooringsProbe.app. It never ships inside Moorings.
    targets.append(.executableTarget(name: "MooringsProbe", exclude: ["Info.plist"]))
    // MooringsMacTests runs the engine's contract suites on the Mac adapters against real Probe
    // windows. It skips without Accessibility access; GitHub's macOS runner has it.
    targets.append(
        .testTarget(
            name: "MooringsMacTests",
            dependencies: ["Moorings", .product(name: "MooringsTesting", package: "core")]
        )
    )
#endif

let package = Package(
    name: "Moorings",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../core")],
    targets: targets
)

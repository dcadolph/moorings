// swift-tools-version: 6.0

import PackageDescription

var targets: [Target] = [
    .target(name: "MooringsCore"),
    .testTarget(
        name: "MooringsCoreTests",
        dependencies: ["MooringsCore"]
    ),
]

// The app layer is AppKit, so other platforms build the core and its tests alone.
#if os(macOS)
targets.append(
    .executableTarget(
        name: "Moorings",
        dependencies: ["MooringsCore"],
        exclude: ["Info.plist"]
    )
)
#endif

// The Windows app is Win32 through WinSDK, so only Windows builds it.
#if os(Windows)
targets.append(
    .executableTarget(
        name: "MooringsWin",
        dependencies: ["MooringsCore"],
        resources: [.embedInCode("moorings.ico")]
    )
)
#endif

let package = Package(
    name: "Moorings",
    platforms: [.macOS(.v14)],
    targets: targets
)

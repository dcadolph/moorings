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

// The Windows app is Win32 through WinSDK, so only Windows builds it.
#if os(Windows)
targets.append(
    .executableTarget(
        name: "MooringsWin",
        dependencies: [.product(name: "MooringsCore", package: "core")],
        resources: [.embedInCode("moorings.ico")]
    )
)
#endif

let package = Package(
    name: "Moorings",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../core")],
    targets: targets
)

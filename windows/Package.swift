// swift-tools-version: 6.0

import PackageDescription

// MooringsWin is the Win32 app through WinSDK, so only Windows builds its target.
var targets: [Target] = []

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
    name: "MooringsWin",
    dependencies: [.package(path: "../core")],
    targets: targets
)

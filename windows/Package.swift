// swift-tools-version: 6.0

import PackageDescription

// MooringsWin is the Win32 app through WinSDK, so only Windows builds its target.
var targets: [Target] = []

#if os(Windows)
    targets.append(
        .executableTarget(
            name: "MooringsWin",
            dependencies: [
                .product(name: "MooringsCore", package: "core"),
                .product(name: "MooringsEngine", package: "core"),
                .product(name: "MooringsTesting", package: "core"),
            ],
            resources: [.embedInCode("moorings.ico")],
            // A Windows program, so a double-click, the Run key, and a link open no console.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])
            ]
        )
    )
#endif

let package = Package(
    name: "MooringsWin",
    dependencies: [.package(path: "../core")],
    targets: targets
)

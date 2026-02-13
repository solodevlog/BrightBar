// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BrightBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BrightBar",
            path: "Sources/BrightBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)

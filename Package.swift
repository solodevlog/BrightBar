// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BrightBar",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/solodevlog/DonateKit.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BrightBar",
            dependencies: ["DonateKit"],
            path: "Sources/BrightBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)

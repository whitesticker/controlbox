// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ControlBoxCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ControlBoxCore", targets: ["ControlBoxCore"])
    ],
    targets: [
        .target(
            name: "ControlBoxCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AudioUnit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)

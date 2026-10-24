// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ControlCenterLab",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "ControlCenterLab", path: "Sources/ControlCenterLab"),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MenuLagLab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MenuLagLab", path: "Sources/MenuLagLab"),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HistoryLab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HistoryLab", path: "Sources/HistoryLab"),
    ]
)

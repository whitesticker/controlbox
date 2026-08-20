// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "IRemoteControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IRemoteControl", targets: ["IRemoteControl"])
    ],
    targets: [
        .target(name: "IRemoteControl")
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ECS",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ECS",
            targets: ["ECS"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ECS"),
        .testTarget(
            name: "ECSTests",
            dependencies: ["ECS"])
    ]
)

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftECS",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SwiftECS",
            targets: ["SwiftECS"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "SwiftECS",
            dependencies: [
                .product(name: "Collections", package: "swift-collections")
            ]),
        .executableTarget(
            name: "Benchmark",
            dependencies: ["SwiftECS"]),
        .testTarget(
            name: "SwiftECSTests",
            dependencies: ["SwiftECS"])
    ]
)

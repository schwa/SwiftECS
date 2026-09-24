// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DemoSupport",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "StarfallSupport",
            targets: ["StarfallSupport"]
        ),
        .library(
            name: "SurvivalSupport",
            targets: ["SurvivalSupport"]
        )
    ],
    dependencies: [.package(name: "SwiftECS", path: "../../../..")],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "StarfallSupport",
            dependencies: [.product(name: "SwiftECS", package: "SwiftECS")]
        ),
        .target(
            name: "SurvivalSupport",
            dependencies: [.product(name: "SwiftECS", package: "SwiftECS")]
        ),
        .testTarget(
            name: "StarfallSupportTests",
            dependencies: ["StarfallSupport"]
        ),
        .testTarget(
            name: "SurvivalSupportTests",
            dependencies: ["SurvivalSupport"]
        )
    ],
    swiftLanguageModes: [.v6]
)

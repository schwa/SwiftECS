// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DemoSupport",
    platforms: [.macOS(.v26), .iOS(.v26), .visionOS(.v26)],
    products: [
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

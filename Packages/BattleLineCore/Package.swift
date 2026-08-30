// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "BattleLineCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "BattleLineCore", targets: ["BattleLineCore"]),
    ],
    targets: [
        .target(name: "BattleLineCore"),
        .testTarget(
            name: "BattleLineCoreTests",
            dependencies: ["BattleLineCore"]
        ),
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Numbers",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "Numbers",
            dependencies: ["SwiftTUI"]),
        .testTarget(
            name: "NumbersTests",
            dependencies: ["Numbers"]),
    ]
)

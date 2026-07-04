// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Colors",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "Colors",
            dependencies: ["SwiftTUI"]
        ),
    ]
)

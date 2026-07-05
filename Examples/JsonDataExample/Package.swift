// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JsonDataExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "JsonDataExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI"),
            ]),
    ]
)

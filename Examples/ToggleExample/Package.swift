// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ToggleExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ToggleExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ])
    ]
)

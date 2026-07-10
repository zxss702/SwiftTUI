// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NavigationExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "NavigationExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ])
    ]
)

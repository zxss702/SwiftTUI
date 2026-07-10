// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PresentationExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "PresentationExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ])
    ]
)

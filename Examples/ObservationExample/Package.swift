// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ObservationExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ObservationExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ])
    ]
)

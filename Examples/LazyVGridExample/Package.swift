// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LazyVGridExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "LazyVGridExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ]
        )
    ]
)

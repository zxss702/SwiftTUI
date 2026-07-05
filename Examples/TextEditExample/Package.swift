// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextEditExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "TextEditExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI")
            ]
        )
    ]
)

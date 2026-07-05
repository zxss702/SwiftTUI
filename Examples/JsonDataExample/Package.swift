// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JsonDataExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../"),
        .package(url: "https://github.com/zxss702/JsonData.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "JsonDataExample",
            dependencies: [
                .product(name: "SwiftTUI", package: "SwiftTUI"),
                .product(name: "JsonData", package: "JsonData")
            ]),
    ]
)

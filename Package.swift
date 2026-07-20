// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftTUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftTUI",
            targets: ["SwiftTUI"]),
    ],
    dependencies: [
         .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
         .package(path: "../JsonData") // 临时本地引用，调试死锁修复；验证后改回 https://github.com/zxss702/JsonData.git
    ],
    targets: [
        .target(
            name: "SwiftTUI",
            dependencies: [
                .product(name: "JsonData", package: "JsonData")
            ],
            exclude: ["SwiftTUI.docc"]),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: ["SwiftTUI"]),
    ]
)

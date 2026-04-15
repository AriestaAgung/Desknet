// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Desknet",
    platforms: [
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "Desknet",
            targets: ["Desknet"]
        ),
    ],
    targets: [
        .target(
            name: "Desknet",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        ),
        .testTarget(
            name: "DesknetTests",
            dependencies: ["Desknet"]
        ),
    ]
)

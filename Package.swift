// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRReviewDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PRReviewDeskCore", targets: ["PRReviewDeskCore"]),
        .executable(name: "PRReviewDeskCoreTests", targets: ["PRReviewDeskCoreTests"])
    ],
    targets: [
        .target(name: "PRReviewDeskCore"),
        .executableTarget(
            name: "PRReviewDeskCoreTests",
            dependencies: ["PRReviewDeskCore"],
            path: "Tests/PRReviewDeskCoreTests"
        )
    ]
)

// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PRReviewDesk",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PRReviewDeskCore", targets: ["PRReviewDeskCore"]),
        .executable(name: "PRReviewDeskApp", targets: ["PRReviewDeskApp"]),
        .executable(name: "PRReviewDeskCoreTests", targets: ["PRReviewDeskCoreTests"])
    ],
    targets: [
        .target(name: "PRReviewDeskCore"),
        .executableTarget(
            name: "PRReviewDeskApp",
            dependencies: ["PRReviewDeskCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "PRReviewDeskCoreTests",
            dependencies: ["PRReviewDeskCore"],
            path: "Tests/PRReviewDeskCoreTests"
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Instagram_Watcher",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Instagram_Watcher",
            targets: ["Instagram_Watcher"]
        ),
    ],
    targets: [
        .target(
            name: "Instagram_Watcher"
        ),
    ]
)

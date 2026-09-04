// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpaceshipDashboard",
    platforms: [
        .macOS(.v14),
        .tvOS(.v17)
    ],
    products: [
        // Shared console: models, themes, widgets, presentation surface and
        // the Bonjour sync layer. Consumed by the macOS executable below and
        // by the tvOS app in AppleTV/.
        .library(name: "AstraConsole", targets: ["AstraConsole"]),
        .executable(name: "SpaceshipDashboard", targets: ["SpaceshipDashboard"])
    ],
    targets: [
        .target(
            name: "AstraConsole",
            path: "Sources/AstraConsole"
        ),
        .executableTarget(
            name: "SpaceshipDashboard",
            dependencies: ["AstraConsole"],
            path: "Sources/SpaceshipDashboard"
        ),
        .testTarget(
            name: "SpaceshipDashboardTests",
            dependencies: ["AstraConsole"],
            path: "Tests/SpaceshipDashboardTests"
        )
    ]
)

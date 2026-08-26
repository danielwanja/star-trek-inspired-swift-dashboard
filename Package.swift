// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SpaceshipDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpaceshipDashboard", targets: ["SpaceshipDashboard"])
    ],
    targets: [
        .executableTarget(
            name: "SpaceshipDashboard",
            path: "Sources/SpaceshipDashboard"
        ),
        .testTarget(
            name: "SpaceshipDashboardTests",
            dependencies: ["SpaceshipDashboard"],
            path: "Tests/SpaceshipDashboardTests"
        )
    ]
)

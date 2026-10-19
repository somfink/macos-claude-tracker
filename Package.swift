// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeTracker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeTracker", targets: ["ClaudeTracker"]),
    ],
    targets: [
        .target(name: "TrackerCore"),
        .executableTarget(
            name: "ClaudeTracker",
            dependencies: ["TrackerCore"]
        ),
        .testTarget(
            name: "TrackerCoreTests",
            dependencies: ["TrackerCore"]
        ),
    ]
)

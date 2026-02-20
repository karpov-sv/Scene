// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scene",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SceneApp", targets: ["SceneApp"])
    ],
    targets: [
        .executableTarget(
            name: "SceneApp",
            path: "Sources/SceneApp"
        ),
        .testTarget(
            name: "SceneAppTests",
            dependencies: ["SceneApp"],
            path: "Tests/SceneAppTests"
        )
    ]
)

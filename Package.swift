// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RoonLyric",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RoonLyric", targets: ["RoonLyric"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "RoonLyric",
            path: "Sources/RoonLyric"
        ),
        .testTarget(
            name: "RoonLyricTests",
            dependencies: ["RoonLyric"],
            path: "Tests/RoonLyricTests"
        )
    ]
)

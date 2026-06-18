// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibeCast",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VibeCast",
            path: "Sources/VibeCast",
            resources: [
                .copy("Resources/web")
            ]
        ),
        .testTarget(
            name: "VibeCastTests",
            dependencies: ["VibeCast"],
            path: "Tests/VibeCastTests"
        )
    ]
)

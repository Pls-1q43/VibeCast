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
                .copy("Resources/web"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/StatusBarIconTemplate.png")
            ]
        ),
        .testTarget(
            name: "VibeCastTests",
            dependencies: ["VibeCast"],
            path: "Tests/VibeCastTests"
        )
    ]
)

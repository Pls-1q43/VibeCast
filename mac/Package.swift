// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibeCast",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMajor(from: "2.9.3"))
    ],
    targets: [
        .executableTarget(
            name: "VibeCast",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
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

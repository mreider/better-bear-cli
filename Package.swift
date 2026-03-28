// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bear-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BearCLICore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/BearCLICore"
        ),
        .executableTarget(
            name: "bcli",
            dependencies: ["BearCLICore"],
            path: "Sources/bcli"
        ),
        .testTarget(
            name: "BearCLITests",
            dependencies: ["BearCLICore"],
            path: "Tests/BearCLITests"
        ),
    ]
)

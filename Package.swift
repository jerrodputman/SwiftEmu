// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SwiftEmu",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/jerrodputman/SwiftNES", branch: "main"),
        .package(url: "https://github.com/ctreffs/SwiftSDL2.git", .upToNextMajor(from: "1.4.0")),
    ],
    targets: [
        .executableTarget(
            name: "SwiftEmu",
            dependencies: [
                "SwiftNES",
                .product(name: "SDL", package: "SwiftSDL2"),
            ]
        ),
    ]
)

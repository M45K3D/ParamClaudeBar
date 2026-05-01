// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ParamClaudeBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.8.1")
    ],
    targets: [
        .executableTarget(
            name: "ParamClaudeBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ParamClaudeBar",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "ParamClaudeBarTests",
            dependencies: ["ParamClaudeBar"],
            path: "Tests/ParamClaudeBarTests"
        )
    ]
)

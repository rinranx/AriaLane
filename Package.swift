// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AriaLane",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AriaLane", targets: ["AriaLane"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "AriaLane",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/AriaLane",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../.."
                ])
            ]
        ),
        .testTarget(
            name: "AriaLaneTests",
            dependencies: ["AriaLane"],
            path: "Tests/AriaLaneTests"
        )
    ]
)

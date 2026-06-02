// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LaughPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "LaughPlayer",
            targets: ["LaughPlayer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LaughPlayer",
            resources: [
                .copy("Resources"),
                .copy("codec-tools")
            ],
            swiftSettings: [
                .define("DIRECT_BUILD")
            ]
        )
    ]
)

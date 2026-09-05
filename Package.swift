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
        .target(
            name: "LibmpvEmbed",
            path: "Sources/LibmpvEmbed",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "LaughPlayer",
            dependencies: [
                "LibmpvEmbed"
            ],
            resources: [
                .copy("Resources"),
                .copy("codec-tools")
            ],
            swiftSettings: [
                .define("DIRECT_BUILD")
            ],
            linkerSettings: [
                .linkedFramework("OpenGL")
            ]
        ),
        .testTarget(
            name: "LaughPlayerTests",
            dependencies: ["LaughPlayer"]
        )
    ]
)

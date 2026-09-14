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
    dependencies: [
        // MobileSAM CoreML runtime (Apache-2.0). Used by MobileSAMSelectionProvider.
        .package(url: "https://github.com/john-rocky/SamKit.git", from: "1.0.0"),
        // In-app updates for shipped .app builds (Help → Check for Updates…).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
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
                "LibmpvEmbed",
                .product(name: "SAMKit", package: "SamKit"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources"),
                .copy("codec-tools")
            ],
            swiftSettings: [
                .define("DIRECT_BUILD"),
                // Silence macOS OpenGL deprecation noise from MpvOpenGLLayer (experimental path).
                .unsafeFlags(["-Xcc", "-DGL_SILENCE_DEPRECATION"])
            ],
            linkerSettings: [
                .linkedFramework("OpenGL")
            ]
        ),
        .testTarget(
            name: "LaughPlayerTests",
            dependencies: ["LaughPlayer"],
            exclude: [
                "Fixtures"
            ]
        )
    ]
)

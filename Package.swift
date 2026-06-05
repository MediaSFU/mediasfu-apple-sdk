// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MediaSFUAppleSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MediaSFUAppleSDK",
            type: .dynamic,
            targets: ["MediaSFUAppleSDK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/MediaSFU/mediasfu-mediasoup-client-apple.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MediaSFUAppleSDK",
            dependencies: [
                .product(
                    name: "MediaSFUMediasoupClient",
                    package: "mediasfu-mediasoup-client-apple",
                    condition: .when(platforms: [.iOS])
                )
            ],
            swiftSettings: [
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "MediaSFUAppleSDKTests",
            dependencies: [
                "MediaSFUAppleSDK"
            ],
            swiftSettings: [
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        )
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MediaSFUAppleSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MediaSFUAppleSDK",
            type: .dynamic,
            targets: ["MediaSFUAppleSDK"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/MediaSFU/mediasfu-mediasoup-client-apple.git", from: "0.1.3")
    ],
    targets: [
        .binaryTarget(
            name: "MediaSFUSDKBinary",
            url: "https://github.com/MediaSFU/mediasfu-apple-sdk/releases/download/0.1.6/MediaSFUSDK-1.0.6.xcframework.zip",
            checksum: "21622c822eea838286f840b2a8bafce693593f880e009d3e5592955da803b853"
        ),
        .target(
            name: "MediaSFUAppleSDK",
            dependencies: [
                "MediaSFUSDKBinary",
                .product(
                    name: "WebRTCBinary",
                    package: "mediasfu-mediasoup-client-apple",
                    condition: .when(platforms: [.iOS])
                ),
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

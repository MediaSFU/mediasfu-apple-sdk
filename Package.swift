// swift-tools-version: 5.10
import PackageDescription
import Foundation

// Maintainer validation can link an unpublished build without changing a released asset.
let artifactsDirectory = ProcessInfo.processInfo.environment["MEDIA_SFU_APPLE_ARTIFACTS_DIR"]
func relativeRuntimePath(_ directory: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().standardizedFileURL
    let destination = URL(fileURLWithPath: directory, relativeTo: root)
        .appendingPathComponent("MediaSFUSDK.xcframework").standardizedFileURL
    let common = zip(root.pathComponents, destination.pathComponents).prefix { $0 == $1 }.count
    return (Array(repeating: "..", count: root.pathComponents.count - common)
        + destination.pathComponents.dropFirst(common)).joined(separator: "/")
}
let runtime: Target = artifactsDirectory.map {
    .binaryTarget(name: "MediaSFUSDKBinary", path: relativeRuntimePath($0))
} ?? .binaryTarget(
    name: "MediaSFUSDKBinary",
    url: "https://github.com/MediaSFU/mediasfu-apple-sdk/releases/download/0.1.7/MediaSFUSDK-1.0.8.xcframework.zip",
    checksum: "094d8aa5b8fe5e3aa597c348f1c695583a4f95c9213311d5c2949a14e95a5720"
)
let nativePackageOverride = ProcessInfo.processInfo.environment["MEDIA_SFU_MEDIASOUP_PACKAGE_PATH"]
let nativePackage: Package.Dependency = nativePackageOverride.map {
    .package(name: "mediasfu-mediasoup-client-apple", path: $0)
} ?? .package(url: "https://github.com/MediaSFU/mediasfu-mediasoup-client-apple.git", from: "0.1.3")
let translationSettings: [SwiftSetting] = artifactsDirectory == nil ? [] : [.define("MEDIA_SFU_HAS_TRANSLATION_VOICES")]

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
        nativePackage
    ],
    targets: [
        runtime,
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
            swiftSettings: translationSettings + [
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "MediaSFUAppleSDKTests",
            dependencies: [
                "MediaSFUAppleSDK"
            ],
            swiftSettings: translationSettings + [
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        )
    ]
)

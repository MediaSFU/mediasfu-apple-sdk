#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
URL="${1:-}"
CHECKSUM="${2:-}"
OUTPUT="${3:-$REPO_ROOT/Package.swift}"
NATIVE_CLIENT_VERSION="${4:-}"

if [ -z "$URL" ] || [ -z "$CHECKSUM" ] || [ -z "$NATIVE_CLIENT_VERSION" ]; then
  echo "Usage: $0 <artifact-url> <checksum> <output-file> <native-client-version>" >&2
  exit 1
fi

if [ "$NATIVE_CLIENT_VERSION" = "0.1.3" ]; then
  echo "Native client 0.1.3 lacks an importable module. Supply a validated module-complete release." >&2
  exit 1
fi

cat > "$OUTPUT" <<EOF
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
        .package(url: "https://github.com/MediaSFU/mediasfu-mediasoup-client-apple.git", from: "$NATIVE_CLIENT_VERSION")
    ],
    targets: [
        .binaryTarget(
            name: "MediaSFUSDKBinary",
            url: "$URL",
            checksum: "$CHECKSUM"
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
                .define("MEDIA_SFU_HAS_TRANSLATION_VOICES", .when(platforms: [.iOS])),
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "MediaSFUAppleSDKTests",
            dependencies: [
                "MediaSFUAppleSDK"
            ],
            swiftSettings: [
                .define("MEDIA_SFU_HAS_TRANSLATION_VOICES", .when(platforms: [.iOS])),
                .define("MEDIA_SFU_HAS_MEDIASOUP_CLIENT", .when(platforms: [.iOS]))
            ]
        )
    ]
)
EOF

echo "Wrote binary-distribution manifest to $OUTPUT"

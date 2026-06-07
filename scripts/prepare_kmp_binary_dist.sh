#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
KOTLIN_REPO="${MEDIA_SFU_KOTLIN_REPO:-$WORKSPACE_ROOT/mediasfu-sdk-kotlin}"
ARTIFACTS_DIR="${MEDIA_SFU_APPLE_ARTIFACTS_DIR:-$REPO_ROOT/Artifacts}"
GRADLE_USER_HOME="${GRADLE_USER_HOME:-$WORKSPACE_ROOT/.gradle-local}"
JAVA_HOME_OVERRIDE="${MEDIA_SFU_JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
BUILD_INTEL_SIM="${MEDIA_SFU_BUILD_INTEL_SIM:-0}"

if [ ! -d "$KOTLIN_REPO" ]; then
  echo "Kotlin repo not found: $KOTLIN_REPO" >&2
  exit 1
fi

VERSION="$(
  sed -n "s/.*spec.version[[:space:]]*=[[:space:]]*'\\([^']*\\)'.*/\\1/p" \
    "$KOTLIN_REPO/shared/shared.podspec" \
    | head -n 1
)"

if [ -z "$VERSION" ]; then
  echo "Unable to detect shared podspec version from $KOTLIN_REPO/shared/shared.podspec" >&2
  exit 1
fi

FRAMEWORK_ARM64="$KOTLIN_REPO/shared/build/bin/iosArm64/podReleaseFramework/MediaSFUSDK.framework"
FRAMEWORK_SIM_ARM64="$KOTLIN_REPO/shared/build/bin/iosSimulatorArm64/podReleaseFramework/MediaSFUSDK.framework"
FRAMEWORK_SIM_X64="$KOTLIN_REPO/shared/build/bin/iosX64/podReleaseFramework/MediaSFUSDK.framework"
COMPOSE_RESOURCES="$KOTLIN_REPO/shared/build/compose/cocoapods/compose-resources"
XCFRAMEWORK_OUT="$ARTIFACTS_DIR/MediaSFUSDK.xcframework"
ZIP_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.xcframework.zip"
CHECKSUM_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.checksum.txt"
METADATA_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.sync.json"
KOTLIN_HEAD="$(git -C "$KOTLIN_REPO" rev-parse HEAD)"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$XCFRAMEWORK_OUT" "$ZIP_OUT" "$CHECKSUM_OUT" "$METADATA_OUT"

GRADLE_CMD=(
  "$KOTLIN_REPO/gradlew"
  "-Dorg.gradle.java.home=$JAVA_HOME_OVERRIDE"
  ":shared:linkPodReleaseFrameworkIosArm64"
  ":shared:linkPodReleaseFrameworkIosSimulatorArm64"
)

if [ "$BUILD_INTEL_SIM" = "1" ]; then
  GRADLE_CMD+=(":shared:linkPodReleaseFrameworkIosX64")
fi

(
  cd "$KOTLIN_REPO"
  GRADLE_USER_HOME="$GRADLE_USER_HOME" "${GRADLE_CMD[@]}"
)

if [ ! -d "$FRAMEWORK_ARM64" ] || [ ! -d "$FRAMEWORK_SIM_ARM64" ]; then
  echo "Expected release frameworks were not generated." >&2
  exit 1
fi

XCODEBUILD_ARGS=(
  -create-xcframework
  -framework "$FRAMEWORK_ARM64"
  -framework "$FRAMEWORK_SIM_ARM64"
)

if [ "$BUILD_INTEL_SIM" = "1" ] && [ -d "$FRAMEWORK_SIM_X64" ]; then
  XCODEBUILD_ARGS+=(-framework "$FRAMEWORK_SIM_X64")
fi

XCODEBUILD_ARGS+=(-output "$XCFRAMEWORK_OUT")
xcodebuild "${XCODEBUILD_ARGS[@]}"

if [ -d "$COMPOSE_RESOURCES" ] && find "$COMPOSE_RESOURCES" -type f | grep -q .; then
  echo "Compose resources were generated under $COMPOSE_RESOURCES." >&2
  echo "Publish-time packaging still needs to place those resources with the app or framework consumer." >&2
fi

ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK_OUT" "$ZIP_OUT"
swift package compute-checksum "$ZIP_OUT" > "$CHECKSUM_OUT"

cat > "$METADATA_OUT" <<EOF
{
  "kotlin_version": "$VERSION",
  "kotlin_commit": "$KOTLIN_HEAD",
  "xcframework": "$(basename "$XCFRAMEWORK_OUT")",
  "zip": "$(basename "$ZIP_OUT")",
  "checksum_file": "$(basename "$CHECKSUM_OUT")"
}
EOF

echo "Prepared KMP Apple artifact:"
echo "  xcframework: $XCFRAMEWORK_OUT"
echo "  zip:         $ZIP_OUT"
echo "  checksum:    $(cat "$CHECKSUM_OUT")"
echo "  metadata:    $METADATA_OUT"
echo
echo "Next release step:"
echo "  Upload $(basename "$ZIP_OUT") as a GitHub Release asset, then render the binary Package.swift manifest."

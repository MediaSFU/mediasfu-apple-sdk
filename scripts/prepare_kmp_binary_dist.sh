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
GRADLE_JVM_ARGS="${MEDIA_SFU_GRADLE_JVM_ARGS:--Xmx8192m -XX:MaxMetaspaceSize=1024m -XX:+HeapDumpOnOutOfMemoryError}"
SIMULATOR_BUILD_TYPE="${MEDIA_SFU_SIMULATOR_BUILD_TYPE:-release}"
SKIP_DEVICE_BUILD="${MEDIA_SFU_SKIP_DEVICE_BUILD:-0}"
SKIP_SIMULATOR_BUILD="${MEDIA_SFU_SKIP_SIMULATOR_BUILD:-0}"

if [ ! -d "$KOTLIN_REPO" ]; then
  echo "Kotlin repo not found: $KOTLIN_REPO" >&2
  exit 1
fi

VERSION="$(
  sed -n "s/.*spec.version[[:space:]]*=[[:space:]]*'\\([^']*\\)'.*/\\1/p" \
    "$KOTLIN_REPO/shared/shared.podspec" \
    | head -n 1
)"

SDK_VERSION="$(
  sed -n 's/^SDK_VERSION=//p' "$KOTLIN_REPO/version.properties" \
    | head -n 1
)"

if [ -z "$VERSION" ]; then
  echo "Unable to detect shared podspec version from $KOTLIN_REPO/shared/shared.podspec" >&2
  exit 1
fi

if [ -z "$SDK_VERSION" ]; then
  echo "Unable to detect SDK_VERSION from $KOTLIN_REPO/version.properties" >&2
  exit 1
fi

if [ "$VERSION" != "$SDK_VERSION" ]; then
  echo "Kotlin Apple version mismatch: shared.podspec=$VERSION, version.properties=$SDK_VERSION" >&2
  exit 1
fi

FRAMEWORK_ARM64="$KOTLIN_REPO/shared/build/bin/iosArm64/podReleaseFramework/MediaSFUSDK.framework"
SIM_FRAMEWORK_DIR_NAME="podReleaseFramework"
SIM_TASK_SUFFIX="Release"

case "$SIMULATOR_BUILD_TYPE" in
  release)
    ;;
  debug)
    SIM_FRAMEWORK_DIR_NAME="podDebugFramework"
    SIM_TASK_SUFFIX="Debug"
    ;;
  *)
    echo "Unsupported MEDIA_SFU_SIMULATOR_BUILD_TYPE: $SIMULATOR_BUILD_TYPE" >&2
    echo "Use 'release' or 'debug'." >&2
    exit 1
    ;;
esac

FRAMEWORK_SIM_ARM64="$KOTLIN_REPO/shared/build/bin/iosSimulatorArm64/$SIM_FRAMEWORK_DIR_NAME/MediaSFUSDK.framework"
FRAMEWORK_SIM_X64="$KOTLIN_REPO/shared/build/bin/iosX64/$SIM_FRAMEWORK_DIR_NAME/MediaSFUSDK.framework"
COMPOSE_RESOURCES="$KOTLIN_REPO/shared/build/compose/cocoapods/compose-resources"
XCFRAMEWORK_OUT="$ARTIFACTS_DIR/MediaSFUSDK.xcframework"
ZIP_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.xcframework.zip"
CHECKSUM_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.checksum.txt"
METADATA_OUT="$ARTIFACTS_DIR/MediaSFUSDK-$VERSION.sync.json"
KOTLIN_HEAD="$(git -C "$KOTLIN_REPO" rev-parse HEAD)"

mkdir -p "$ARTIFACTS_DIR"
for output in "$XCFRAMEWORK_OUT" "$ZIP_OUT" "$CHECKSUM_OUT" "$METADATA_OUT" "$ARTIFACTS_DIR/compose-resources"; do
  if [ -e "$output" ]; then
    echo "Output already exists: $output. Use a new MEDIA_SFU_APPLE_ARTIFACTS_DIR." >&2
    exit 1
  fi
done

run_gradle_task() {
  local task="$1"
  (
    cd "$KOTLIN_REPO"
    JAVA_HOME="$JAVA_HOME_OVERRIDE" GRADLE_USER_HOME="$GRADLE_USER_HOME" \
      "$KOTLIN_REPO/gradlew" \
      "-Dorg.gradle.java.home=$JAVA_HOME_OVERRIDE" \
      "-Dorg.gradle.jvmargs=$GRADLE_JVM_ARGS" \
      --no-daemon \
      "$task"
  )
}

if [ "$SKIP_DEVICE_BUILD" != "1" ]; then
  run_gradle_task ":shared:linkPodReleaseFrameworkIosArm64"
fi

if [ "$SKIP_SIMULATOR_BUILD" != "1" ]; then
  run_gradle_task ":shared:linkPod${SIM_TASK_SUFFIX}FrameworkIosSimulatorArm64"
fi

if [ "$BUILD_INTEL_SIM" = "1" ]; then
  if [ "$SKIP_SIMULATOR_BUILD" != "1" ]; then
    run_gradle_task ":shared:linkPod${SIM_TASK_SUFFIX}FrameworkIosX64"
  fi
fi

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

# Static frameworks do not copy resources into the application. Retain the sidecar
# and let the consuming target copy it into its main bundle (see copy_compose_resources.sh).
mkdir -p "$ARTIFACTS_DIR/compose-resources"
if [ -d "$COMPOSE_RESOURCES" ]; then
  ditto "$COMPOSE_RESOURCES" "$ARTIFACTS_DIR/compose-resources"
fi
RESOURCE_COUNT="$(find "$ARTIFACTS_DIR/compose-resources" -type f | wc -l | tr -d ' ')"

ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK_OUT" "$ZIP_OUT"
swift package compute-checksum "$ZIP_OUT" > "$CHECKSUM_OUT"

cat > "$METADATA_OUT" <<EOF
{
  "kotlin_version": "$VERSION",
  "kotlin_commit": "$KOTLIN_HEAD",
  "simulator_build_type": "$SIMULATOR_BUILD_TYPE",
  "compose_resource_files": $RESOURCE_COUNT,
  "compose_resources": "compose-resources",
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
echo "  simulator:   $SIMULATOR_BUILD_TYPE"
echo
echo "This artifact is local and unpublished."
echo "Before release, choose a new SDK/package version and immutable asset URL,"
echo "validate the native-media dependency, and render the reviewed SwiftPM manifest."
echo "Publishing requires separate release authorization."

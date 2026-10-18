# KMP Binary Sync

The hosted iOS MediaSFU runtime is exported from the Kotlin Multiplatform `MediaSFUSDK` framework in [`mediasfu-sdk-kotlin`](https://github.com/MediaSFU/mediasfu-sdk-kotlin).

Apple consumers should not need to rebuild that Kotlin repo themselves. The expected release flow is:

1. publish meaningful iOS/KMP changes from `mediasfu-sdk-kotlin`
2. build the release Apple framework slices from that repo
3. package them into `MediaSFUSDK.xcframework`
4. zip the xcframework, compute its SwiftPM checksum, and publish it as a GitHub Release asset
5. render the Apple repo's binary `Package.swift` manifest against that uploaded artifact

Helpers in this repo:

- `Package.swift`
  - public SwiftPM manifest that points at the hosted prebuilt `MediaSFUSDK` release asset
- `Package.source.swift`
  - maintainer-only source manifest for local validation when working on the Apple bridge package itself
- `scripts/prepare_kmp_binary_dist.sh`
  - builds `MediaSFUSDK` release frameworks from the sibling `mediasfu-sdk-kotlin` checkout
  - supports `MEDIA_SFU_SIMULATOR_BUILD_TYPE=debug` when a usable simulator slice is needed without waiting on a release-simulator rebuild
  - supports `MEDIA_SFU_SKIP_DEVICE_BUILD=1` / `MEDIA_SFU_SKIP_SIMULATOR_BUILD=1` to reuse already-built framework slices during packaging
  - creates `Artifacts/MediaSFUSDK.xcframework`
  - zips it and computes the SwiftPM checksum
- `scripts/render_binary_package_manifest.sh`
  - writes a binary-target `Package.swift` manifest once the release asset URL and checksum are known

The bridge source in this repo is kept compatible with both module names used during local and packaged integration:

- `MediaSFUSDK`
- `shared`

That lets release packaging move toward a proper prebuilt Apple artifact without breaking local source-based validation in the meantime.

## Validate an unpublished translation runtime

Use JDK 17 and a new, empty artifact directory for each build. The helper refuses
to replace existing outputs. Keep release device and simulator builds enabled:

```sh
export MEDIA_SFU_APPLE_ARTIFACTS_DIR="$(mktemp -d)"
export MEDIA_SFU_JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export JAVA_HOME="$MEDIA_SFU_JAVA_HOME"
MEDIA_SFU_SKIP_DEVICE_BUILD=0 MEDIA_SFU_SKIP_SIMULATOR_BUILD=0 \
  MEDIA_SFU_SIMULATOR_BUILD_TYPE=release \
  bash scripts/prepare_kmp_binary_dist.sh
```

The current distribution contains iOS arm64 device and arm64 simulator slices.
Intel simulator support is not part of this distribution.

While `MEDIA_SFU_APPLE_ARTIFACTS_DIR` is set, `Package.swift` makes the actual
`MediaSFUSDKBinary` dependency point at that directory's XCFramework and enables
the new native translation adapter. The existing hosted asset remains unchanged;
it predates the native adapter. Unset the variable to resolve that published
version. `Package.source.swift` is for bridge-only development and is not
translation/runtime acceptance evidence.

Run package tests on an installed iOS simulator, then build the
[translation sample](Examples/TranslationVoices/README.md) with the same artifact
directory. An iOS build fails if neither KMP runtime module is importable.

```sh
xcodebuild -scheme MediaSFUAppleSDK \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The helper also retains `compose-resources` next to the XCFramework and records
its file count in the sync metadata. Static framework linkage does not install
these resources in the main application bundle. Add an app build phase:

```sh
scripts/copy_compose_resources.sh "$MEDIA_SFU_APPLE_ARTIFACTS_DIR" \
  "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
```

The sample includes this phase. An empty directory is valid when this runtime has no Compose resource
files. Future distributions with resources must ship this sidecar and copy it;
the XCFramework archive alone is insufficient for those distributions.

Public release packaging is a separate step. Use a new immutable asset URL and
its exact checksum, and ship any required resources. The manifest renderer enables
the native adapter for a runtime built from this source. Do not point that manifest
at a previously published framework that lacks the new exports.

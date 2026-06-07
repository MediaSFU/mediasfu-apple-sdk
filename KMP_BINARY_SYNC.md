# KMP Binary Sync

The hosted iOS MediaSFU runtime is exported from the Kotlin Multiplatform `MediaSFUSDK` framework in [`mediasfu-sdk-kotlin`](https://github.com/MediaSFU/mediasfu-sdk-kotlin).

Apple consumers should not need to rebuild that Kotlin repo themselves. The expected release flow is:

1. publish meaningful iOS/KMP changes from `mediasfu-sdk-kotlin`
2. build the release Apple framework slices from that repo
3. package them into `MediaSFUSDK.xcframework`
4. zip the xcframework, compute its SwiftPM checksum, and publish it as a GitHub Release asset
5. render the Apple repo's binary `Package.swift` manifest against that uploaded artifact

Helpers in this repo:

- `scripts/prepare_kmp_binary_dist.sh`
  - builds `MediaSFUSDK` release frameworks from the sibling `mediasfu-sdk-kotlin` checkout
  - creates `Artifacts/MediaSFUSDK.xcframework`
  - zips it and computes the SwiftPM checksum
- `scripts/render_binary_package_manifest.sh`
  - writes a binary-target `Package.swift` manifest once the release asset URL and checksum are known

The bridge source in this repo is kept compatible with both module names used during local and packaged integration:

- `MediaSFUSDK`
- `shared`

That lets release packaging move toward a proper prebuilt Apple artifact without breaking local source-based validation in the meantime.

# MediaSFU Apple SDK

MediaSFU Apple SDK is the Swift package layer that connects Apple host apps to the MediaSFU Kotlin Multiplatform runtime and the standalone mediasoup/WebRTC Apple client.

It is distinct from `mediasfu-mediasoup-client-apple`:

- `mediasfu-mediasoup-client-apple` is the generic mediasoup/WebRTC client. It can be used by any mediasoup user, with or without MediaSFU.
- `mediasfu-apple-sdk` is the MediaSFU SDK integration layer for Apple apps. It provides bridge contracts, adapters, and installation helpers for MediaSFU room/media flows.

## Package

```swift
.package(url: "https://github.com/MediaSFU/mediasfu-apple-sdk", from: "0.1.0")
```

Then add the product to your app target:

```swift
.product(name: "MediaSFUAppleSDK", package: "mediasfu-apple-sdk")
```

## What It Provides

- `MediaSFUNativeMediasoupBridge` protocols that match the native media operations expected by the MediaSFU KMP runtime.
- Placeholder and device-backed bridge implementations for smoke tests and production wiring.
- Adapter contracts for connecting the SDK to `MediaSFUMediasoupClient`.
- JSON helpers and typed errors for transport, produce, consume, pause, resume, and stats operations.
- Conditional KMP installation helpers that remain build-safe when the generated `shared` framework is not present.

## Relationship To The Apple Client

For a pure mediasoup client, use the standalone package:

```swift
.package(url: "https://github.com/MediaSFU/mediasfu-mediasoup-client-apple", from: "0.1.0")
```

This SDK package depends on that client when real iOS media transport support is enabled.

## Platform Status

- iOS and iPadOS are the primary targets.
- macOS currently supports safe-mode builds and tests for bridge contracts.
- Real mediasoup/WebRTC native binding is opt-in through the standalone Apple client package.

## Documentation

See [USAGE.md](USAGE.md) for integration examples.

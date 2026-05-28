# MediaSFU Apple SDK Usage

This package is for Apple apps that need the MediaSFU SDK runtime to use native mediasoup/WebRTC transports.

For a generic mediasoup client without MediaSFU room/socket/API behavior, use `mediasfu-mediasoup-client-apple` directly.

## Swift Package Manager

```swift
.package(url: "https://github.com/MediaSFU/mediasfu-apple-sdk", from: "0.1.0")
```

Add the product to your app target:

```swift
.product(name: "MediaSFUAppleSDK", package: "mediasfu-apple-sdk")
```

## Placeholder Smoke Test

Use the placeholder bridge only to verify host app wiring:

```swift
import MediaSFUAppleSDK

let bridge = PlaceholderMediasoupBridge()
let sendTransport = bridge.createSendTransport(params: [:])
print(sendTransport.connectionState())
```

## Device-Backed Integration

Production apps should create a device backed by the standalone Apple mediasoup client, then install it into the MediaSFU runtime bridge:

```swift
import MediaSFUAppleSDK
import MediaSFUMediasoupClient

let device = MSCDevice()
let sdkAdapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: device)
let bridge = DeviceBackedMediasoupBridge(device: sdkAdapter)
```

Call the KMP install helper before joining a MediaSFU room from the Kotlin Multiplatform SDK:

```swift
MediaSFUKmpBridgeInstaller.installBridgeIfSupported(bridge)
```

## Notes

- Real media support requires the standalone Apple client package to be built with the required WebRTC/libmediasoupclient native artifacts.
- The bridge can still build in safe mode for host-app scaffolding and tests.
- The generated KMP `shared` module name can vary by integration. If the installer cannot find it, adjust the import/symbol mapping in the host app bridge layer.

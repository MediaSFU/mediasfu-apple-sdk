<p align="center">
  <img src="https://www.mediasfu.com/logo192.png" width="100" alt="MediaSFU Logo">
</p>

<p align="center">
  <a href="https://twitter.com/media_sfu">
    <img src="https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white" alt="Twitter" />
  </a>
  <a href="https://www.mediasfu.com/forums">
    <img src="https://img.shields.io/badge/Community-Forum-blue?style=for-the-badge&logo=discourse&logoColor=white" alt="Community Forum" />
  </a>
  <a href="https://github.com/MediaSFU">
    <img src="https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white" alt="Github" />
  </a>
  <a href="https://www.mediasfu.com/">
    <img src="https://img.shields.io/badge/Website-4285F4?style=for-the-badge&logo=google-chrome&logoColor=white" alt="Website" />
  </a>
  <a href="https://www.youtube.com/channel/UCELghZRPKMgjih5qrmXLtqw">
    <img src="https://img.shields.io/badge/YouTube-FF0000?style=for-the-badge&logo=youtube&logoColor=white" alt="Youtube" />
  </a>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="License: MIT" />
  </a>
  <a href="https://mediasfu.com">
    <img src="https://img.shields.io/badge/Built%20with-MediaSFU-blue?style=flat-square" alt="Built with MediaSFU" />
  </a>
  <a href="https://developer.apple.com/swift/">
    <img src="https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift" />
  </a>
  <a href="https://developer.apple.com/ios/">
    <img src="https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS" />
  </a>
</p>

---

# MediaSFU Apple SDK

**Build premium, real-time voice, video, and collaborative features on iOS and iPadOS in minutes.**

MediaSFU provides prebuilt, fully-featured room components with real-time video/audio, screen sharing, recording, chat, polls, whiteboards, real-time translation, and more. Drop the Swift Package into your Xcode project and connect to a room with a few lines of code.

The current Apple runtime uses the same state-driven modern room renderer as the React, React Native, Flutter, and Kotlin SDKs. A hosted room has one controller that owns its socket, media transports, room state, modals, and visible interface.

📖 **[Detailed Integration & API Guide (USAGE.md) →](USAGE.md)** | 🌐 **[mediasfu.com](https://www.mediasfu.com/)**

---

## ⚡ Why MediaSFU?

| Without MediaSFU | With MediaSFU |
| :--- | :--- |
| Months of WebRTC, TURN/STUN, and codec setup | Swift package dependency → done in minutes |
| $1–5 per 1,000 minutes (Twilio, Daily) | **$0.10 per 1,000 minutes** (10–50× cheaper) |
| Designing video grids and moderation cards from scratch | Prebuilt components & layouts included |
| Manual integration of AI models & translation APIs | Built-in AI agents, transcription, & translation |

---

## ⚠️ Backend Server Requirement

**MediaSFU is a client-side SDK and requires a backend media server to operate.**
You can use the managed cloud service or host your own:

* **☁️ MediaSFU Cloud**: Managed, globally scalable cloud service at [mediasfu.com](https://www.mediasfu.com). This is the default route. Provide your `apiUserName` and `apiKey`; leave `localLink` empty.
* **🏠 MediaSFU Open / CE (Self-Hosted)**: Open-source media server. Set `localLink` only when you are connecting to your own self-hosted MediaSFU server.

---

## 🚀 Quick Start (SwiftPM Integration)

### 1. Add Dependency in Xcode

Add the Swift Package URL to your Xcode project dependencies:
```
https://github.com/MediaSFU/mediasfu-apple-sdk.git
```

This package resolves to hosted prebuilt XCFrameworks. You do not need to clone or build the Kotlin Multiplatform repository.

### 2. Configure Permissions (`Info.plist`)

Ensure your app requests camera and mic permissions:
```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to stream your video to room participants.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access to record and stream your audio.</string>
```

### 3. Initialize & Launch a Room

```swift
import MediaSFUAppleSDK
import SwiftUI

struct MediaSFUView: UIViewControllerRepresentable {
    private let nativeDevice = MSCDevice()

    func makeUIViewController(context: Context) -> UIViewController {
        let bridge = MediaSFUIosHostBridge()
        let config = bridge.makeLaunchConfig()
        
        // 1. Authentication
        config.apiUserName = "your-api-username"
        config.apiKey = "your-api-key"
        config.connectMediaSFU = true
        
        // Optional: set localLink only for self-hosted MediaSFU Open / CE.
        // Leave this empty for MediaSFU Cloud.
        // config.localLink = "https://your-ce-instance.example.com"
        
        // 2. Room Configuration
        config.userName = "Alice Smith"
        config.action = "create" // "create" or "join"
        config.eventType = "conference"
        config.autoProceed = true // Skip pre-join check screen
        
        // 3. Connect the native mediasoup/WebRTC engine.
        // Keep this device alive for the lifetime of the room view.
        MediaSFUKmpBridgeInstaller.installMediaSFUMediasoupClientBridgeIfSupported(device: nativeDevice)
        
        return bridge.makeHostViewController(config: config)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

### Embedding the standard interface in your own layout

Keep the controller returned by `makeHostViewController(config:)` mounted for the entire room session. Embed that same controller wherever the standard MediaSFU interface should appear; do not create another bridge or host controller to render the room a second time. This preserves one socket, one set of media transports, and one modal/navigation lifecycle.

For a completely custom interface, keep the same controller mounted as the room runtime and render the native tracks returned by `latestLocalVideoTrack()` and `latestRemoteVideoTracks()`. See the [headless integration guide](USAGE.md#-headless-mode-custom-ui-integration) for the complete lifecycle and renderer example.

### Backend-proxy room handoff

Use this mode when your application backend creates or joins the MediaSFU room.
The iOS app receives only the room-scoped `roomName`, `secret`, and `link` from
that backend response:

```swift
config.apiUserName = "roomUser"
config.apiKey = String(repeating: "0", count: 64)
config.connectMediaSFU = true

config.action = "join"
config.userName = displayName
config.roomName = response.roomName
config.roomApiToken = response.secret
config.roomLink = response.link
config.autoProceed = true
```

The first two values are non-secret bootstrap values used only for launch
validation. Before the socket connection, the SDK applies the room-scoped
handoff: `roomName` becomes the socket username, `secret` becomes the socket
token, and `link` selects the media node. The SDK does not make another
account-authenticated create/join request.

Do not put a real account API key in an iOS app that uses this pattern. Keep it
on your application server. Also leave `localLink` empty: an application backend
for MediaSFU Cloud is not a self-hosted MediaSFU Open / CE instance.

---

## 💎 Platform Features

* **Real-Time Video & Audio**: Multi-party adaptive video grids, portrait frame overrides, and high-fidelity audio.
* **GPU-Accelerated Effects**: On-device person segmentation for virtual backgrounds (blur, image, colors) powered by Metal & CoreImage.
* **Screen Sharing**: Native iOS broadcast screen-share extension support.
* **Moderation & Administrative Control**: Waiting room approvals, participant mute/ban/removal, and co-host delegation.
* **Cloud Recording**: Track-based cloud recordings with customizable layouts, watermarks, and background colors.
* **Collaboration Tools**: Real-time collaborative whiteboards, instant poll creation and voting, and direct/group text chats.

---

## 🏗️ Configuration Reference

| Parameter | Description |
| :--- | :--- |
| `apiUserName` | Your MediaSFU account username (MediaSFU Cloud). |
| `apiKey` | Your MediaSFU account API key. |
| `localLink` | Self-hosted MediaSFU Open / CE server URL. Leave empty for MediaSFU Cloud. |
| `connectMediaSFU` | Toggle connecting to signaling services (`true`/`false`). |
| `action` | Session flow action (`"create"` or `"join"`). |
| `roomName` | Target room identifier for join actions. |
| `userName` | Display name of the local participant. |
| `eventType` | Event room layout profile (`"conference"`, `"broadcast"`, `"webinar"`, `"chat"`). |
| `roomApiToken` | Room-scoped `secret` returned by an application backend. Use with `roomName` and `roomLink`. |
| `roomLink` | Media-node link returned with a backend room handoff. This is not `localLink`. |

---

## 🔒 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Maintainers

Release packaging notes live in [KMP_BINARY_SYNC.md](KMP_BINARY_SYNC.md). App developers do not need those steps for normal Swift Package Manager installation.

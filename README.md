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

**Build premium, real-time voice, video, and collaborative features on iOS, iPadOS, and macOS in minutes.**

MediaSFU provides prebuilt, fully-featured room components with real-time video/audio, screen sharing, recording, chat, polls, whiteboards, real-time translation, and more. Drop the Swift Package into your Xcode project and connect to a room with a few lines of code.

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

* **☁️ MediaSFU Cloud**: Managed, globally scalable cloud service at [mediasfu.com](https://www.mediasfu.com). Requires your `apiUserName` and `apiKey`.
* **🏠 MediaSFU Open (Self-Hosted)**: Open-source media server. Point the SDK's `localLink` parameter to your self-hosted domain.

---

## 🚀 Quick Start (SwiftPM Integration)

### 1. Add Dependency in Xcode

Add the Swift Package URL to your Xcode project dependencies:
```
https://github.com/MediaSFU/mediasfu-apple-sdk.git
```

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
import MediaSFUMediasoupClient
import SwiftUI

struct MediaSFUView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let bridge = MediaSFUIosHostBridge()
        let config = bridge.makeLaunchConfig()
        
        // 1. Authentication
        config.apiUserName = "your-api-username"
        config.apiKey = "your-api-key"
        config.connectMediaSFU = true
        
        // Optional: Set localLink for self-hosting (MediaSFU Open)
        // config.localLink = "https://your-ce-instance.example.com"
        
        // 2. Room Configuration
        config.userName = "Alice Smith"
        config.action = "create" // "create" or "join"
        config.eventType = "conference"
        config.autoProceed = true // Skip pre-join check screen
        
        // 3. Connect Native Mediasoup Engine
        let nativeDevice = MSCDevice()
        let adapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: nativeDevice)
        let mediaBridge = DeviceBackedMediasoupBridge(device: adapter)
        MediaSFUKmpBridgeInstaller.installBridgeIfSupported(mediaBridge)
        
        return bridge.makeHostViewController(config: config)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

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
| `localLink` | The URL of your self-hosted MediaSFU CE server. |
| `connectMediaSFU` | Toggle connecting to signaling services (`true`/`false`). |
| `action` | Session flow action (`"create"` or `"join"`). |
| `roomName` | Target room identifier for join actions. |
| `userName` | Display name of the local participant. |
| `eventType` | Event room layout profile (`"conference"`, `"broadcast"`, `"webinar"`, `"chat"`). |

---

## 🔒 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

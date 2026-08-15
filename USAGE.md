# MediaSFU Apple SDK Integration & Deep-Dive Usage Guide

The **`mediasfu-apple-sdk`** package is the official integration layer for native iOS and iPadOS Swift applications. It connects your Apple client to the high-level **MediaSFU** room, socket, and media orchestration engine.

Use this guide when you want to add the hosted MediaSFU room UI to an app, or when you need lower-level programmatic control after the room is mounted.

---

## 📖 Table of Contents

1. [Architectural Overview](#-architectural-overview)
2. [Configuration Parameters Reference](#-configuration-parameters-reference)
3. [Hosted UI Mode (SwiftUI & UIKit)](#-hosted-ui-mode-swiftui--uikit)
4. [Headless Mode (Custom UI Integration)](#-headless-mode-custom-ui-integration)
5. [Programmatic Media Controls (The Power API)](#-programmatic-media-controls-the-power-api)
6. [Advanced Features & Room Moderation](#-advanced-features--room-moderation)
   - [Event Types](#event-types)
   - [Roles & Permissions](#roles--permissions)
   - [Waiting Room & Access Control](#waiting-room--access-control)
   - [Cloud Recording Control](#cloud-recording-control)
   - [Polls & Engagement](#polls--engagement)
7. [Custom Media Rendering (SwiftUI & UIKit)](#-custom-media-rendering-swiftui--uikit)
8. [Troubleshooting & Support](#-troubleshooting--support)

---

## 🏛️ Architectural Overview

MediaSFU uses a three-layer architecture to deliver high-performance streaming with minimal integration overhead:

```
┌──────────────────────────────────────────────┐
│           Your SwiftUI / UIKit App           │
│   (Custom UI Views or Host View Controllers) │
└──────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│             MediaSFU Apple SDK               │
│  (Config Launchers, Bridge Adapters, Shims)  │
└──────────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│           MediaSFU Core Runtime             │
│ (Room state, WebRTC/Socket orchestration,    │
│  Metal-accelerated Virtual Backgrounds)      │
└──────────────────────────────────────────────┘
```

The Apple SDK sits between your application and the core Multiplatform runtime, translating low-level WebRTC/mediasoup C++ connection states into native Swift interfaces.

---

## ⚙️ Configuration Parameters Reference

The primary entry point for configuring a MediaSFU session is the `MediaSFUIosLaunchConfig` object. Below is the complete reference of parameters:

### Authentication & Server Routing

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `apiUserName` | `String` | Yes (Cloud) | Your MediaSFU account username. Get this from the [MediaSFU Dashboard](https://mediasfu.com). |
| `apiKey` | `String` | Yes (Cloud) | Your MediaSFU application API key. Used to sign and validate session requests. |
| `localLink` | `String` | Optional | Set this **only** when connecting to a self-hosted **MediaSFU Open / Community Edition (CE)** server, e.g. `https://your-ce-instance.example.com`. Leave empty for MediaSFU Cloud. |
| `connectMediaSFU` | `Bool` | Yes | Set to `true` to establish signaling connections with MediaSFU servers. Set to `false` for offline UI testing/previews. |

### Room Configuration & Actions

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `action` | `String` | `"create"` | `"create"` to host a new room session, `"join"` to connect to an existing room. |
| `roomName` | `String` | `""` | The unique room identifier (e.g., `"s1234567"`). Must be supplied when `action` is `"join"`. |
| `userName` | `String` | `""` | The display name of the local participant. |
| `eventType` | `String` | `"conference"` | The room profile. Supported profiles: `"conference"`, `"broadcast"`, `"webinar"`, `"chat"`. See [Event Types](#event-types). |
| `durationMinutes` | `Int` | `60` | The session duration limit (for new rooms). |
| `capacity` | `Int` | `100` | The maximum allowed concurrent participants (for new rooms). |
| `secureCode` | `String` | `""` | Optional passcode to restrict admin access when creating a room. |
| `adminPasscode` | `String` | `""` | Passcode provided by a joining participant to request admin privileges. |
| `islevel` | `String` | `"0"` | `"0"` for standard participant, `"2"` for admin/host. |
| `autoProceed` | `Bool` | `false` | `true` to skip the pre-join camera/mic check screen and join the room instantly. |

---

## 🎨 Hosted UI Mode (SwiftUI & UIKit)

Hosted UI is the easiest way to add video calling to your app. The SDK loads a fully featured, pre-built, theme-aware user interface complete with video grids, participant lists, chat, recording, and modal controls.

### SwiftUI Integration

Wrap the host controller in a SwiftUI `UIViewControllerRepresentable`:

```swift
import SwiftUI
import MediaSFUAppleSDK

struct MediaSFURoomView: UIViewControllerRepresentable {
    let apiUserName: String
    let apiKey: String
    let userName: String
    var action: String = "join"
    var roomName: String = ""
    var localLink: String? = nil
    var autoProceed: Bool = true
    private let nativeDevice = MSCDevice()
    
    func makeUIViewController(context: Context) -> UIViewController {
        let bridge = MediaSFUIosHostBridge()
        let config = bridge.makeLaunchConfig()
        
        // MediaSFU Cloud credentials.
        config.apiUserName = apiUserName
        config.apiKey = apiKey
        config.localLink = localLink ?? "" // Leave empty for MediaSFU Cloud.
        config.connectMediaSFU = true
        
        // Room Identity
        config.userName = userName
        config.action = action
        config.roomName = roomName
        config.eventType = "conference"
        
        // Moderation & Flow
        config.islevel = action == "create" ? "2" : "0"
        config.autoProceed = autoProceed

        // Required for real media publishing/receiving.
        // Keep this device alive while the room is active.
        MediaSFUKmpBridgeInstaller.installMediaSFUMediasoupClientBridgeIfSupported(device: nativeDevice)
        
        return bridge.makeHostViewController(config: config)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// SwiftUI Usage Example
struct MainAppView: View {
    @State private var showRoom = false
    
    var body: some View {
        VStack {
            Button("Join Room") {
                showRoom = true
            }
        }
        .fullScreenCover(isPresented: $showRoom) {
            MediaSFURoomView(
                apiUserName: "my_api_username",
                apiKey: "my_secret_api_key",
                userName: "Alice Smith",
                action: "join",
                roomName: "s1234567"
            )
            .ignoresSafeArea()
        }
    }
}
```

### UIKit Presentation

```swift
import UIKit
import MediaSFUAppleSDK

class MainMenuViewController: UIViewController {
    private let nativeDevice = MSCDevice()
    
    func launchMediaSFURoom() {
        let bridge = MediaSFUIosHostBridge()
        let config = bridge.makeLaunchConfig()
        
        // Set configuration parameters
        config.apiUserName = "your-api-username"
        config.apiKey = "your-api-key"
        config.connectMediaSFU = true
        config.userName = "Bob Miller"
        config.action = "create"
        config.eventType = "conference"
        config.autoProceed = false // Show pre-join setup screen

        MediaSFUKmpBridgeInstaller.installMediaSFUMediasoupClientBridgeIfSupported(device: nativeDevice)
        
        let roomViewController = bridge.makeHostViewController(config: config)
        roomViewController.modalPresentationStyle = .fullScreen
        self.present(roomViewController, animated: true, completion: nil)
    }
}
```

---

## 🏗️ Headless Mode (Custom UI Integration)

If you want to build a completely custom, branded UI, you can run the SDK in **Headless Mode** (`returnUI = false`). This allows you to leverage MediaSFU's robust WebRTC connection state management and Socket signaling while maintaining complete control over your views.

```swift
import SwiftUI
import MediaSFUAppleSDK
import MediaSFUMediasoupClient

class CustomRoomController: ObservableObject {
    private var nativeDevice: MSCDevice?
    private var mediaBridge: DeviceBackedMediasoupBridge?
    
    @Published var participants: [ParticipantInfo] = []
    @Published var activeStreams: [RTCVideoTrack] = []
    @Published var isMuted: Bool = false
    @Published var isCameraOn: Bool = false
    
    func initializeRoomConnection() {
        let nativeDevice = MSCDevice()
        self.nativeDevice = nativeDevice
        
        let adapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: nativeDevice)
        let bridge = DeviceBackedMediasoupBridge(device: adapter)
        self.mediaBridge = bridge
        
        // Install media engine shim into KMP runtime
        MediaSFUKmpBridgeInstaller.installBridgeIfSupported(bridge)
        
        // 1. Establish REST & Socket connections
        // 2. Register observers for stream events
    }
    
    func toggleAudio() {
        // Trigger microphone state change
        isMuted.toggle()
    }
    
    func toggleVideo() {
        // Trigger camera state change
        isCameraOn.toggle()
    }
}
```

---

## ⚡ Programmatic Media Controls (The Power API)

Once a hosted room is actively presented, you can invoke media actions programmatically from your host Swift application using `MediaSFUIosHostBridge`:

```swift
let bridge = MediaSFUIosHostBridge()
// Present your room controller...

// Toggle local microphone
bridge.triggerToggleAudio()

// Toggle local camera feed
bridge.triggerToggleVideo()

// Start/Stop screen-share capture
bridge.triggerToggleScreenShare()

// Switch front/rear camera
bridge.triggerSwitchCamera()
```

> [!NOTE]
> Programmatic triggers are queued and safely ignored if the room UI has not completed its initial connection handshake.

---

## 🛡️ Advanced Features & Room Moderation

### Event Types
MediaSFU configures layout and permission defaults based on the event profile:

* **`"conference"`**: Standard multi-party meeting. All participants can unmute, share video, and initiate screen sharing.
* **`"broadcast"`**: High-performance streaming mode. One host publishes video/audio, and all other participants receive the stream passively.
* **`"webinar"`**: Moderated seminar model. Host and designated panelists can publish streams. Audience members can raise hands to request promotion.
* **`"chat"`**: High-density text and audio communication. Video grids are disabled to save network resources.

### Roles & Permissions
You can delegate responsibilities or restrict actions by adjusting participant levels:

```swift
// Host setup
config.islevel = "2" // Level "2" = Full Admin / Host controls enabled
config.secureCode = "my-secure-admin-passcode"

// Standard Participant setup
config.islevel = "0" // Level "0" = Participant role (no moderation controls)
```

### Waiting Room & Access Control
When Waiting Room moderation is enabled on the server, the host receives access requests dynamically:

```swift
// As the host, you can handle waiting room requests programmatically:
func admitParticipant(id: String) {
    // Emit 'allowUserIn' on the signaling transport
}

func denyParticipant(id: String) {
    // Reject request
}
```

### Cloud Recording Control
Start, pause, and stop cloud-side recordings with customized visual profiles:

```swift
// Trigger cloud recording options
func startRoomRecording() {
    let recordingOptions = [
        "recordingType": "video",
        "includeAudio": true,
        "videoLayout": "grid",
        "backgroundColor": "#0F172A" // Premium dark slate background
    ]
    // Emit start recording request
}
```

### Polls & Engagement
Create and vote on interactive polls:

```swift
// Host creates a poll
func launchCustomPoll() {
    let pollQuestion = "Which feature should we build next?"
    let options = ["Virtual Backgrounds", "Noise Cancellation", "Custom Layouts"]
    
    // Publish poll data to participants
}
```

---

## 🎥 Custom Media Rendering (SwiftUI & UIKit)

When building custom UIs, remote participant video tracks are delivered as `RTCVideoTrack` instances. Wrap WebRTC's native rendering views to display them in SwiftUI:

```swift
import SwiftUI
import WebRTC

struct NativeVideoRenderer: UIViewRepresentable {
    let videoTrack: RTCVideoTrack
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        videoTrack.add(view)
        return view
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}
    
    static func dismantleUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Prevent layout leaks by detaching the renderer
        // when the participant leaves or cell is recycled
    }
}
```

---

## ⚠️ Troubleshooting & Support

### 1. Codec Negotiations and RTX/APT Errors
* **Symptom**: Low-level console warnings: `MSCDevice: load() failed due to invalid APT parameter`.
* **Fix**: Ensure your `MSCDevice` instance is wrapped using `MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device:)`. The factory applies runtime sanitation to codecs and RTX attributes to match native Apple WebRTC behaviors before loading capability configurations.

### 2. UI Freezes or AVFoundation Deadlocks
* **Symptom**: The camera preview freezes or the app halts for 4-10 seconds when toggling the camera.
* **Fix**: Ensure the background camera processor is only released when video streaming is completely stopped. Releasing the frame processor during active captures can cause thread contention on AVFoundation's dispatch queue. Use the SDK's built-in `MediaSFUKmpBridgeInstaller` which manages the hardware session lifecycles automatically.

### 3. Local Link Connection Failure
* **Symptom**: Connection timeout when using `localLink` pointing to a self-hosted server.
* **Fix**: iOS requires secure connections (`https`) for WebRTC. If you are self-hosting on local servers, ensure you supply a valid HTTPS endpoint with trusted certificates. If using self-signed development certificates, you must implement a custom `ServerCertificateValidationCallback` on your `MediaSfuClientOptions`.

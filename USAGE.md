# MediaSFU Apple SDK Integration and Usage Guide

The **`mediasfu-apple-sdk`** package is the official integration layer for native iOS and iPadOS Swift applications. It connects your Apple client to the high-level **MediaSFU** room, socket, and media orchestration engine.

Use this guide when you want to add the hosted MediaSFU room UI to an app, or when you need lower-level programmatic control after the room is mounted.

---

## 📖 Table of Contents

1. [Architectural Overview](#-architectural-overview)
2. [Configuration Parameters Reference](#-configuration-parameters-reference)
3. [Hosted UI Mode (SwiftUI & UIKit)](#-hosted-ui-mode-swiftui--uikit)
4. [Headless Mode (Custom UI Integration)](#-headless-mode-custom-ui-integration)
5. [Programmatic Media Controls](#-programmatic-media-controls)
6. [Advanced Features & Room Moderation](#-advanced-features--room-moderation)
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
| `apiUserName` | `String` | Yes | Your account username in the standard Cloud flow. For a backend room handoff, use the non-secret bootstrap value `"roomUser"`; the SDK replaces it before the socket connection. |
| `apiKey` | `String` | Yes | Your account API key in the standard Cloud flow. For a backend room handoff, use a shape-valid non-secret bootstrap value such as `String(repeating: "0", count: 64)` and keep the real key on the server. |
| `localLink` | `String` | Optional | Set this **only** when connecting to a self-hosted **MediaSFU Open / Community Edition (CE)** server, e.g. `https://your-ce-instance.example.com`. Leave empty for MediaSFU Cloud. |
| `connectMediaSFU` | `Bool` | Yes | Set to `true` to establish signaling connections with MediaSFU servers. Set to `false` for offline UI testing/previews. |

### Room Configuration & Actions

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `action` | `String` | `"create"` | `"create"` to host a new room session, `"join"` to connect to an existing room. |
| `roomName` | `String` | `""` | The unique room identifier (e.g., `"s1234567"`). Must be supplied when `action` is `"join"`. |
| `roomApiToken` | `String` | `""` | Optional room-scoped secret returned by your backend's MediaSFU create/join response. When supplied, the SDK uses `roomName` as the socket username and this value as the socket token. |
| `roomLink` | `String` | `""` | Optional media-node link returned with `roomApiToken`. Supply this together with `roomApiToken` to reuse an already-created/joined cloud room. |
| `userName` | `String` | `""` | The display name of the local participant. |
| `eventType` | `String` | `"conference"` | The room profile. Supported profiles: `"conference"`, `"broadcast"`, `"webinar"`, `"chat"`. See [Event Types](#event-types). |
| `durationMinutes` | `Int` | `60` | The session duration limit (for new rooms). |
| `capacity` | `Int` | `100` | The maximum allowed concurrent participants (for new rooms). |
| `secureCode` | `String` | `""` | Optional passcode to restrict admin access when creating a room. |
| `adminPasscode` | `String` | `""` | Passcode provided by a joining participant to request admin privileges. |
| `islevel` | `String` | `"0"` | Participant level assigned by your application: `"0"` for listener/viewer, `"1"` for speaker/participant, or `"2"` for admin/host. |
| `autoProceed` | `Bool` | `false` | `true` to skip the pre-join camera/mic check screen and join the room instantly. |

---

## 🎨 Hosted UI Mode (SwiftUI & UIKit)

Hosted UI is the easiest way to add video calling to your app. The SDK loads a fully featured, pre-built, theme-aware user interface complete with video grids, participant lists, chat, recording, and modal controls.

The hosted controller renders the maintained modern component tree from the room state it owns. This is the Apple equivalent of `ModernMediasfuGenericHead` in the React, React Native, Flutter, and Kotlin SDKs: the renderer does not create a second socket, transport set, or copy of room state.

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

For a custom app flow, set `autoProceed` to `true` and mount the returned host
controller inside your own SwiftUI or UIKit interface. The controller owns the
room, socket, and media lifecycle even when your app renders the visible controls.

Create one `MediaSFUIosHostBridge` and call `makeHostViewController` once per room session. Retain both objects until the room ends. For a hybrid layout, place that same controller in the part of your interface where the standard room UI should render. For a fully custom layout, keep it mounted with non-zero bounds and render its published native tracks in your own views. Creating a second host controller is not a rendering shortcut; it creates a second room engine.

### Reusing a backend create/join response

If your application server already creates or joins the room, pass the
room-scoped values from that response to the native bridge and set
`autoProceed` to `true`:

```swift
// Non-secret bootstrap values used only until the room handoff is applied.
config.apiUserName = "roomUser"
config.apiKey = String(repeating: "0", count: 64)
config.connectMediaSFU = true

config.action = "join"
config.roomName = response.roomName
config.roomApiToken = response.secret
config.roomLink = response.link
config.userName = displayName
config.autoProceed = true
```

The bootstrap values satisfy launch validation; they are not used to
authenticate the room. The SDK uses the returned `roomName` as the socket
`apiUserName`, the returned `secret` as the socket `apiToken`, and `link` as the
media node. It therefore does not issue a second create/join request with an
account API key.

Keep account credentials on your server when using this handoff pattern. Leave
`localLink` empty: proxying a managed Cloud room through your application
backend does not turn it into a self-hosted MediaSFU Open / CE connection. Leave
`roomApiToken` and `roomLink` empty only when you intentionally want the SDK to
perform the standard account-authenticated Cloud create/join flow itself.

Keep the returned MediaSFU host controller mounted for the lifetime of the room.
It may sit behind an opaque app surface with hit testing and accessibility
disabled, but it must retain non-zero bounds and remain in the view hierarchy.
Use `latestLocalVideoTrack()` and `latestRemoteVideoTracks()` to bind native
`RTCVideoTrack` objects to your custom renderers.

```swift
import SwiftUI
import MediaSFUAppleSDK

struct RoomRuntimeView: UIViewControllerRepresentable {
    let bridge: MediaSFUIosHostBridge
    let config: MediaSFUIosLaunchConfig

    func makeUIViewController(context: Context) -> UIViewController {
        bridge.makeHostViewController(config: config)
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
```

---

## ⚡ Programmatic Media Controls

Once a hosted room is actively presented, you can invoke media actions programmatically from your host Swift application using `MediaSFUIosHostBridge`:

```swift
// Use the same bridge instance that created the mounted room controller.

// Toggle local microphone
bridge.triggerToggleAudio()

// Toggle local camera feed
bridge.triggerToggleVideo()

// Start/Stop screen-share capture
bridge.triggerToggleScreenShare()

```

> [!NOTE]
> Each method returns `true` when the room accepted the action. A `false` result
> means the room is not ready for that control yet.

---

## 🛡️ Advanced Features & Room Moderation

### Event Types
Set `eventType` when creating a room so the hosted UI and room policy use the
matching profile:

* **`"conference"`**: Multi-participant meeting.
* **`"broadcast"`**: Host-led broadcast with an audience.
* **`"webinar"`**: Moderated host, panelist, and attendee session.
* **`"chat"`**: Chat-focused room.

### Roles & Permissions
Use the participant level supplied by your application flow:

```swift
config.islevel = "0" // listener or viewer
config.islevel = "1" // speaker or participant
config.islevel = "2" // admin or host
```

Room settings and the server remain authoritative. Do not assign host level from
untrusted client input. For an admin join, provide the matching room passcode:

```swift
config.islevel = "2"
config.adminPasscode = adminPasscode
```

### Hosted moderation tools

The hosted room UI provides waiting-room requests, participant controls,
recording, polls, and other tools when they are enabled for the room and the
current participant has permission. A custom shell can open supported hosted
modals through the same bridge instance:

```swift
bridge.triggerShowModal(name: "waiting")
bridge.triggerShowModal(name: "recording")
```

Supported names are `media_settings`, `display_settings`, `recording`, `cohost`,
`requests`, `waiting`, and `confirm_exit`. The method returns `false` when the
room is not ready.

---

## 🎥 Custom Media Rendering (SwiftUI & UIKit)

When building custom UIs, remote participant video tracks are delivered as `RTCVideoTrack` instances. Wrap WebRTC's native rendering views to display them in SwiftUI:

```swift
import SwiftUI
import WebRTC

struct NativeVideoRenderer: UIViewRepresentable {
    let videoTrack: RTCVideoTrack

    final class Coordinator {
        var track: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        context.coordinator.track = videoTrack
        videoTrack.add(view)
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        guard context.coordinator.track !== videoTrack else { return }
        context.coordinator.track?.remove(view)
        context.coordinator.track = videoTrack
        videoTrack.add(view)
    }

    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.track?.remove(view)
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
* **Fix**: Use an HTTPS endpoint with a certificate trusted by iOS and ensure the host satisfies your app's App Transport Security policy.

import SwiftUI
import MediaSFUAppleSDK

@MainActor
private final class Room: ObservableObject {
    let host = MediaSFUIosHostBridge()
    let device = MSCDevice()
    @Published var controller: UIViewController?
    lazy var voices = MediaSFUKmpTranslationVoiceSession(host: host)

    func join(name: String, room: String, token: String, link: String) {
        let config = host.makeLaunchConfig()
        config.apiUserName = "roomUser"
        config.apiKey = String(repeating: "0", count: 64)
        config.connectMediaSFU = true
        config.action = "join"
        config.userName = name
        config.roomName = room
        config.roomApiToken = token
        config.roomLink = link
        config.autoProceed = true
        MediaSFUKmpBridgeInstaller.installMediaSFUMediasoupClientBridgeIfSupported(device: device)
        controller = host.makeHostViewController(config: config)
    }
}

private struct HostedRoom: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

@main
struct TranslationVoicesApp: App {
    @StateObject private var room = Room()
    @State private var name = ""
    @State private var roomName = ""
    @State private var token = ""
    @State private var link = ""
    @State private var showingVoices = false

    var body: some Scene {
        WindowGroup {
            if let controller = room.controller {
                VStack(spacing: 0) {
                    Button("Translation voice") { showingVoices = true }
                        .padding()
                    HostedRoom(controller: controller)
                }
                .sheet(isPresented: $showingVoices) {
                    NavigationView {
                        MediaSFUTranslationVoicePicker(session: room.voices, outputLanguage: "fr")
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingVoices = false }
                                }
                            }
                    }
                }
            } else {
                NavigationView {
                    Form {
                        Section(header: Text("Join an owned test room")) {
                            Text("Obtain a room-scoped handoff from your application backend. Keep account and provider credentials on the server.")
                            TextField("Display name", text: $name)
                            TextField("Room name", text: $roomName)
                            SecureField("Room-scoped token", text: $token)
                            TextField("Room media link", text: $link)
                                .keyboardType(.URL).textInputAutocapitalization(.never)
                            Button("Join room") { room.join(name: name, room: roomName, token: token, link: link) }
                                .disabled([name, roomName, token, link].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        }
                        Text(MediaSFUKmpBridgeInstaller.isKmpModuleAvailable() ? "MediaSFU runtime linked" : "MediaSFU runtime unavailable")
                            .accessibilityIdentifier("runtimeLinkStatus")
                    }
                    .navigationTitle("Translation voices")
                }
            }
        }
    }
}

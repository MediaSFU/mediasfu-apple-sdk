import Foundation

public enum RealMediasoupBindingEngine {
    public static func makeDeviceBackend(
        binding: MediaSFUAssumedLibmediasoupDeviceBinding
    ) -> MediaSFURawLibmediasoupDeviceBackend {
        let engine = MediaSFUAssumedLibmediasoupDeviceEngine(binding: binding)
        return MediaSFUExpectedLibmediasoupDeviceBackend(engine: engine)
    }

    public static func makeWrappedDevice(
        binding: MediaSFUAssumedLibmediasoupDeviceBinding
    ) -> MediaSFULibmediasoupDevice {
        MediaSFULibmediasoupDeviceWrapper(backend: makeDeviceBackend(binding: binding))
    }

    public static func makeInstallableAdapter(
        binding: MediaSFUAssumedLibmediasoupDeviceBinding
    ) -> MediaSFUDeviceAdapter {
        LibmediasoupClientDeviceAdapter(device: makeWrappedDevice(binding: binding))
    }
}

public enum RealMediasoupBindingIntegrationNotes {
    public static let summary = "Provide a concrete MediaSFUAssumedLibmediasoupDeviceBinding backed by the chosen iOS mediasoup library, then install it through RealMediasoupBindingEngine.makeInstallableAdapter(binding:)."

    public static let requiredSteps: [String] = [
        "Create a device binding that constructs native send/recv transports from MediaSFURawTransportOptions.",
        "Forward native DTLS connect requests into onConnectNeeded handlers with the JSON expected by shared Kotlin.",
        "Forward native produce requests into onProduceNeeded handlers and return the producer id supplied by shared Kotlin.",
        "Forward native connection-state changes into observeState so transport state stays in sync.",
        "Return producer and consumer bindings that wrap native track lifecycle methods and compatible WebRTC tracks."
    ]
}

// Template notes for the eventual concrete implementation:
// 1. Replace the binding protocol conformers with wrappers around the chosen native library.
// 2. Keep all JSON payloads untouched unless the library requires conversion at the boundary.
// 3. Ensure returned tracks come from the same WebRTC binary family as the KMP framework.
// 4. Prefer injecting the native binding into this file rather than changing Kotlin bridge contracts.
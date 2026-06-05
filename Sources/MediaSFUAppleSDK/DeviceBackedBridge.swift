import Foundation

public final class DeviceBackedMediasoupBridge: MediaSFUNativeMediasoupBridge, MediaSFUNativeLoadableMediasoupBridge {
    private let device: MediaSFUDeviceAdapter
    private var loadedRtpCapabilitiesJson: String?

    public init(device: MediaSFUDeviceAdapter) {
        self.device = device
    }

    public func load(routerRtpCapabilitiesJson: String) throws {
        guard let loadableDevice = device as? MediaSFULoadableDeviceAdapter else {
            // Some device adapters do not expose an explicit load step and can
            // still create transports successfully from router params alone.
            // Treat this as a no-op instead of failing the Kotlin readiness gate.
            NSLog("[MediaSFUIosBridge] Device adapter does not implement explicit RTP load; caching capabilities only.")
            loadedRtpCapabilitiesJson = routerRtpCapabilitiesJson
            return
        }
        try loadableDevice.load(routerRtpCapabilitiesJson: routerRtpCapabilitiesJson)
        loadedRtpCapabilitiesJson = (device as? MediaSFUCurrentRtpCapabilitiesProvider)?.currentRtpCapabilitiesJson()
            ?? routerRtpCapabilitiesJson
    }

    public func currentRtpCapabilitiesJson() -> String? {
        return (device as? MediaSFUCurrentRtpCapabilitiesProvider)?.currentRtpCapabilitiesJson()
            ?? loadedRtpCapabilitiesJson
    }

    public func createSendTransport(params: [String : Any?]) -> MediaSFUNativeSendTransportHandle {
        do {
            let transport = try device.createSendTransport(params: params)
            return AdapterBackedSendTransportHandle(adapter: transport)
        } catch {
            NSLog("[MediaSFUIosBridge] createSendTransport failed: %@", String(describing: error))
            return FailingSendTransportHandle(error: error)
        }
    }

    public func createRecvTransport(params: [String : Any?]) -> MediaSFUNativeRecvTransportHandle {
        do {
            let transport = try device.createRecvTransport(params: params)
            return AdapterBackedRecvTransportHandle(adapter: transport)
        } catch {
            NSLog("[MediaSFUIosBridge] createRecvTransport failed: %@", String(describing: error))
            return FailingRecvTransportHandle(error: error)
        }
    }
}

final class AdapterBackedSendTransportHandle: MediaSFUNativeSendTransportHandle {
    private let adapter: MediaSFUSendTransportAdapter

    init(adapter: MediaSFUSendTransportAdapter) {
        self.adapter = adapter
    }

    var id: String { adapter.id }
    func connectionState() -> String { adapter.connectionState }
    func close() { adapter.close() }
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) { adapter.setOnConnect(listener) }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) { adapter.setOnConnectionStateChange(listener) }
    func setOnProduce(_ listener: MediaSFUNativeProduceListener?) { adapter.setOnProduce(listener) }

    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) -> MediaSFUNativeProducerHandle {
        do {
            let producer = try adapter.produce(
                track: track,
                encodingsJson: encodingsJson,
                codecOptionsJson: codecOptionsJson,
                codecJson: codecJson,
                appDataJson: appDataJson
            )
            return AdapterBackedProducerHandle(adapter: producer)
        } catch {
            NSLog("[MediaSFUIosBridge] sendTransport.produce failed transportId=%@: %@", adapter.id, String(describing: error))
            return FailingProducerHandle(error: error)
        }
    }
}

final class AdapterBackedRecvTransportHandle: MediaSFUNativeRecvTransportHandle {
    private let adapter: MediaSFURecvTransportAdapter

    init(adapter: MediaSFURecvTransportAdapter) {
        self.adapter = adapter
    }

    var id: String { adapter.id }
    func connectionState() -> String { adapter.connectionState }
    func close() { adapter.close() }
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) { adapter.setOnConnect(listener) }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) { adapter.setOnConnectionStateChange(listener) }

    func consume(id: String, producerId: String, kind: String, rtpParametersJson: String) -> MediaSFUNativeConsumerHandle {
        do {
            let consumer = try adapter.consume(id: id, producerId: producerId, kind: kind, rtpParametersJson: rtpParametersJson)
            return AdapterBackedConsumerHandle(adapter: consumer)
        } catch {
            NSLog("[MediaSFUIosBridge] recvTransport.consume failed transportId=%@: %@", adapter.id, String(describing: error))
            return FailingConsumerHandle(error: error, kind: kind)
        }
    }
}

final class AdapterBackedProducerHandle: MediaSFUNativeProducerHandle {
    private let adapter: MediaSFUProducerAdapter

    init(adapter: MediaSFUProducerAdapter) {
        self.adapter = adapter
    }

    var id: String { adapter.id }
    var kind: String { adapter.kind }
    func isPaused() -> Bool { adapter.paused }
    func close() { adapter.close() }
    func pause() { adapter.pause() }
    func resume() { adapter.resume() }
    func replaceTrack(_ track: MediaSFUNativeTrack) {
        try? adapter.replaceTrack(track)
    }
    func statsJson() -> String? { nil }
}

final class AdapterBackedConsumerHandle: MediaSFUNativeConsumerHandle {
    private let adapter: MediaSFUConsumerAdapter

    init(adapter: MediaSFUConsumerAdapter) {
        self.adapter = adapter
    }

    var id: String { adapter.id }
    var kind: String { adapter.kind }
    var track: MediaSFUNativeTrack? { adapter.track }
    func isPaused() -> Bool { adapter.paused }
    func close() { adapter.close() }
    func pause() { adapter.pause() }
    func resume() { adapter.resume() }
    func statsJson() -> String? { adapter.getStatsJson() }
}

final class FailingSendTransportHandle: MediaSFUNativeSendTransportHandle {
    private let error: Error

    init(error: Error) { self.error = error }

    var id: String { compactErrorId(prefix: "send-error", error: error) }
    func connectionState() -> String { "failed" }
    func close() {}
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) {
        _ = listener
        NSLog("[MediaSFUIosBridge] FailingSendTransportHandle.setOnConnect ignored due to transport error: %@", String(describing: error))
    }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) {
        listener?("failed")
    }
    func setOnProduce(_ listener: MediaSFUNativeProduceListener?) {
        _ = listener
        NSLog("[MediaSFUIosBridge] FailingSendTransportHandle.setOnProduce ignored due to transport error: %@", String(describing: error))
    }
    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) -> MediaSFUNativeProducerHandle {
        _ = track
        _ = encodingsJson
        _ = codecOptionsJson
        _ = codecJson
        _ = appDataJson
        return FailingProducerHandle(error: error)
    }
}

final class FailingRecvTransportHandle: MediaSFUNativeRecvTransportHandle {
    private let error: Error

    init(error: Error) { self.error = error }

    var id: String { compactErrorId(prefix: "recv-error", error: error) }
    func connectionState() -> String { "failed" }
    func close() {}
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) {
        _ = listener
        NSLog("[MediaSFUIosBridge] FailingRecvTransportHandle.setOnConnect ignored due to transport error: %@", String(describing: error))
    }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) {
        listener?("failed")
    }
    func consume(id: String, producerId: String, kind: String, rtpParametersJson: String) -> MediaSFUNativeConsumerHandle {
        FailingConsumerHandle(error: error, kind: kind)
    }
}

final class FailingProducerHandle: MediaSFUNativeProducerHandle {
    private let error: Error

    init(error: Error) { self.error = error }

    var id: String { compactErrorId(prefix: "producer-error", error: error) }
    var kind: String { "audio" }
    func isPaused() -> Bool { true }
    func close() {}
    func pause() {}
    func resume() {}
    func replaceTrack(_ track: MediaSFUNativeTrack) {
        _ = error
    }
    func statsJson() -> String? { nil }
}

final class FailingConsumerHandle: MediaSFUNativeConsumerHandle {
    private let error: Error
    private let kindValue: String

    init(error: Error, kind: String) {
        self.error = error
        self.kindValue = kind
    }

    var id: String { compactErrorId(prefix: "consumer-error", error: error) }
    var kind: String { kindValue }
    var track: MediaSFUNativeTrack? { nil }
    func isPaused() -> Bool { true }
    func close() {}
    func pause() {}
    func resume() { _ = error }
    func statsJson() -> String? { nil }
}

private func compactErrorId(prefix: String, error: Error) -> String {
    let raw = String(describing: error)
    let cleaned = raw
        .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "", options: .regularExpression)
    let maxLen = 120
    let suffix = cleaned.isEmpty ? "unknown" : String(cleaned.prefix(maxLen))
    return "\(prefix):\(suffix)"
}
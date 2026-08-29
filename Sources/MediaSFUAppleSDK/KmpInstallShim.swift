import Foundation

#if canImport(MediaSFUSDK)
import MediaSFUSDK
typealias SharedIosNativeConnectListener = IosNativeConnectListener
typealias SharedIosNativeConsumerHandle = IosNativeConsumerHandle
typealias SharedIosNativeLoadableMediasoupBridge = IosNativeLoadableMediasoupBridge
typealias SharedIosNativeProduceListener = IosNativeProduceListener
typealias SharedIosNativeProducerHandle = IosNativeProducerHandle
typealias SharedIosNativeRecvTransportHandle = IosNativeRecvTransportHandle
typealias SharedIosNativeSendTransportHandle = IosNativeSendTransportHandle
#elseif canImport(shared)
import shared
#endif

#if canImport(MediaSFUMediasoupClient)
import MediaSFUMediasoupClient
#endif

public enum MediaSFUKmpBridgeInstaller {
    public static func isKmpModuleAvailable() -> Bool {
        #if canImport(MediaSFUSDK) || canImport(shared)
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    public static func installBridgeIfSupported(_ bridge: MediaSFUNativeMediasoupBridge) -> Bool {
        #if canImport(MediaSFUSDK)
        IosMediasoupBridgeKt.installIosNativeMediasoupBridge(bridge: SharedBridgeAdapter(bridge: bridge))
        return true
        #elseif canImport(shared)
        SharedKt.installIosNativeMediasoupBridge(bridge: SharedBridgeAdapter(bridge: bridge))
        return true
        #else
        _ = bridge
        return false
        #endif
    }

    @discardableResult
    public static func installPlaceholderBridgeIfSupported() -> Bool {
        installBridgeIfSupported(PlaceholderMediasoupBridge())
    }

    @discardableResult
    public static func installDeviceBackedBridgeIfSupported(device: MediaSFUDeviceAdapter) -> Bool {
        installBridgeIfSupported(DeviceBackedMediasoupBridge(device: device))
    }

    #if canImport(MediaSFUMediasoupClient)
    @discardableResult
    public static func installMediaSFUMediasoupClientBridgeIfSupported(device: MSCDevice) -> Bool {
        let adapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: device)
        return installDeviceBackedBridgeIfSupported(device: adapter)
    }
    #endif

    public static func bridgeInstallModeDescription() -> String {
        #if canImport(MediaSFUSDK) || canImport(shared)
        return "Native media support is available. Install the MediaSFU mediasoup client bridge before presenting a room."
        #else
        return "Native media support requires the MediaSFU SDK framework. Add the Apple SDK package before installing the mediasoup client bridge."
        #endif
    }
}

#if canImport(MediaSFUSDK) || canImport(shared)
import WebRTC

final class SharedBridgeAdapter: SharedIosNativeLoadableMediasoupBridge {
    private let bridge: MediaSFUNativeMediasoupBridge

    init(bridge: MediaSFUNativeMediasoupBridge) {
        self.bridge = bridge
    }

    #if canImport(MediaSFUSDK)
    func createSendTransport(params: [String : Any]) -> SharedIosNativeSendTransportHandle {
        let mapped = params.mapValues { Optional($0) }
        return SharedSendTransportAdapter(handle: bridge.createSendTransport(params: mapped))
    }

    func createRecvTransport(params: [String : Any]) -> SharedIosNativeRecvTransportHandle {
        let mapped = params.mapValues { Optional($0) }
        return SharedRecvTransportAdapter(handle: bridge.createRecvTransport(params: mapped))
    }
    #else
    func createSendTransport(params: [AnyHashable : Any?]) -> SharedIosNativeSendTransportHandle {
        let mapped = params.reduce(into: [String: Any?]()) { partial, item in
            partial[String(describing: item.key)] = item.value
        }
        return SharedSendTransportAdapter(handle: bridge.createSendTransport(params: mapped))
    }

    func createRecvTransport(params: [AnyHashable : Any?]) -> SharedIosNativeRecvTransportHandle {
        let mapped = params.reduce(into: [String: Any?]()) { partial, item in
            partial[String(describing: item.key)] = item.value
        }
        return SharedRecvTransportAdapter(handle: bridge.createRecvTransport(params: mapped))
    }
    #endif

    func loadRtpCapabilitiesJson(rtpCapabilitiesJson: String) -> String? {
        guard let loadableBridge = bridge as? MediaSFUNativeLoadableMediasoupBridge else {
            return "bridge-cast-to-loadable-failed"
        }

        do {
            try loadableBridge.load(routerRtpCapabilitiesJson: rtpCapabilitiesJson)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func currentRtpCapabilitiesJson() -> String? {
        (bridge as? MediaSFUNativeLoadableMediasoupBridge)?.currentRtpCapabilitiesJson()
    }
}

final class SharedSendTransportAdapter: SharedIosNativeSendTransportHandle {
    private let handle: MediaSFUNativeSendTransportHandle
    private let pendingProduceKindLock = NSLock()
    private var pendingProduceKinds: [String] = []

    init(handle: MediaSFUNativeSendTransportHandle) {
        self.handle = handle
    }

    var id: String { handle.id }

    func connectionState() -> String { handle.connectionState() }

    func close() { handle.close() }

    func setOnConnect(listener: SharedIosNativeConnectListener?) {
        handle.setOnConnect(listener.map { listener in
            { dtlsJson, callback, errback in
                listener.onConnect(dtlsParametersJson: dtlsJson, callback: callback, errback: { error in
                    #if canImport(MediaSFUSDK)
                    errback(error.asError())
                    #else
                    errback(error)
                    #endif
                })
            }
        })
    }

    func setOnConnectionStateChange(listener: ((String) -> Void)?) {
        handle.setOnConnectionStateChange(listener)
    }

    func setOnProduce(listener: SharedIosNativeProduceListener?) {
        handle.setOnProduce(listener.map { listener in
            { [weak self] kind, rtpJson, appDataJson, callback, errback in
                let hintedKind = self?.consumePendingProduceKind()
                let effectiveKind = hintedKind ?? kind
                if let hintedKind, hintedKind != kind {
                    NSLog("[MediaSFUIosBridge] produce kind override native=%@ effective=%@ transportId=%@", kind, hintedKind, self?.id ?? "unknown")
                }
                listener.onProduce(kind: effectiveKind, rtpParametersJson: rtpJson, appDataJson: appDataJson, callback: callback, errback: { error in
                    #if canImport(MediaSFUSDK)
                    errback(error.asError())
                    #else
                    errback(error)
                    #endif
                })
            }
        })
    }

    func produce(
        track: RTCMediaStreamTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) -> SharedIosNativeProducerHandle {
        enqueuePendingProduceKind(kind(for: track))
        return SharedProducerAdapter(
            handle: handle.produce(
                track: track,
                encodingsJson: encodingsJson,
                codecOptionsJson: codecOptionsJson,
                codecJson: codecJson,
                appDataJson: appDataJson
            )
        )
    }

    private func enqueuePendingProduceKind(_ kind: String) {
        pendingProduceKindLock.lock()
        pendingProduceKinds.append(kind)
        pendingProduceKindLock.unlock()
    }

    private func consumePendingProduceKind() -> String? {
        pendingProduceKindLock.lock()
        defer { pendingProduceKindLock.unlock() }
        guard !pendingProduceKinds.isEmpty else { return nil }
        return pendingProduceKinds.removeFirst()
    }

    private func kind(for track: RTCMediaStreamTrack) -> String {
        if track is RTCAudioTrack { return "audio" }
        if track is RTCVideoTrack { return "video" }
        return track.kind
    }
}

final class SharedRecvTransportAdapter: SharedIosNativeRecvTransportHandle {
    private let handle: MediaSFUNativeRecvTransportHandle

    init(handle: MediaSFUNativeRecvTransportHandle) {
        self.handle = handle
    }

    var id: String { handle.id }

    func connectionState() -> String { handle.connectionState() }

    func close() { handle.close() }

    func setOnConnect(listener: SharedIosNativeConnectListener?) {
        handle.setOnConnect(listener.map { listener in
            { dtlsJson, callback, errback in
                listener.onConnect(dtlsParametersJson: dtlsJson, callback: callback, errback: { error in
                    #if canImport(MediaSFUSDK)
                    errback(error.asError())
                    #else
                    errback(error)
                    #endif
                })
            }
        })
    }

    func setOnConnectionStateChange(listener: ((String) -> Void)?) {
        handle.setOnConnectionStateChange(listener)
    }

    func consume(id: String, producerId: String, kind: String, rtpParametersJson: String) -> SharedIosNativeConsumerHandle {
        SharedConsumerAdapter(handle: handle.consume(id: id, producerId: producerId, kind: kind, rtpParametersJson: rtpParametersJson))
    }
}

final class SharedProducerAdapter: SharedIosNativeProducerHandle {
    private let handle: MediaSFUNativeProducerHandle

    init(handle: MediaSFUNativeProducerHandle) {
        self.handle = handle
    }

    var id: String { handle.id }
    var kind: String { handle.kind }
    func isPaused() -> Bool { handle.isPaused() }
    func close() { handle.close() }
    func pause() { handle.pause() }
    func resume() { handle.resume() }
    func replaceTrack(track: RTCMediaStreamTrack) { handle.replaceTrack(track) }
}

final class SharedConsumerAdapter: SharedIosNativeConsumerHandle {
    private let handle: MediaSFUNativeConsumerHandle

    init(handle: MediaSFUNativeConsumerHandle) {
        self.handle = handle
    }

    var id: String { handle.id }
    var kind: String { handle.kind }
    var track: RTCMediaStreamTrack? { handle.track }
    func isPaused() -> Bool { handle.isPaused() }
    func close() { handle.close() }
    func pause() { handle.pause() }
    func resume() { handle.resume() }
}
#endif

import Foundation

#if canImport(shared)
import shared
#endif

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient)
import MediaSFUMediasoupClient
#endif

public enum MediaSFUKmpBridgeInstaller {
    public static func isKmpModuleAvailable() -> Bool {
        #if canImport(shared)
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    public static func installBridgeIfSupported(_ bridge: MediaSFUNativeMediasoupBridge) -> Bool {
        #if canImport(shared)
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

    #if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient)
    @discardableResult
    public static func installMediaSFUMediasoupClientBridgeIfSupported(device: MSCDevice) -> Bool {
        guard device.nativeIntegrationMode == .fullyBundledNative else {
            return false
        }

        let adapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: device)
        return installDeviceBackedBridgeIfSupported(device: adapter)
    }
    #endif

    public static func bridgeInstallModeDescription() -> String {
        #if canImport(shared)
        return "KMP bridge available: prefer a device-backed bridge for real mediasoup integration, or use a placeholder bridge for scaffolding and smoke tests."
        #else
        return "KMP bridge unavailable: the Swift package can build, but bridge installation requires the generated shared framework."
        #endif
    }
}

#if canImport(shared) && MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC

final class SharedBridgeAdapter: SharedIosNativeMediasoupBridge {
    private let bridge: MediaSFUNativeMediasoupBridge

    init(bridge: MediaSFUNativeMediasoupBridge) {
        self.bridge = bridge
    }

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

    func loadRtpCapabilitiesJson(rtpCapabilitiesJson: String) -> String? {
        guard let loadableBridge = bridge as? MediaSFUNativeLoadableMediasoupBridge else {
            return nil
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

    init(handle: MediaSFUNativeSendTransportHandle) {
        self.handle = handle
    }

    var id: String { handle.id }

    func connectionState() -> String { handle.connectionState() }

    func close() { handle.close() }

    func setOnConnect(listener: SharedIosNativeConnectListener?) {
        handle.setOnConnect(listener.map { listener in
            { dtlsJson, callback, errback in
                listener.onConnect(dtlsParametersJson: dtlsJson, callback: callback, errback: { error in errback(error) })
            }
        })
    }

    func setOnConnectionStateChange(listener: ((String) -> Void)?) {
        handle.setOnConnectionStateChange(listener)
    }

    func setOnProduce(listener: SharedIosNativeProduceListener?) {
        handle.setOnProduce(listener.map { listener in
            { kind, rtpJson, appDataJson, callback, errback in
                listener.onProduce(kind: kind, rtpParametersJson: rtpJson, appDataJson: appDataJson, callback: callback, errback: { error in errback(error) })
            }
        })
    }

    func produce(track: RTCMediaStreamTrack, encodingsJson: String?, appDataJson: String?) -> SharedIosNativeProducerHandle {
        SharedProducerAdapter(handle: handle.produce(track: track, encodingsJson: encodingsJson, appDataJson: appDataJson))
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
                listener.onConnect(dtlsParametersJson: dtlsJson, callback: callback, errback: { error in errback(error) })
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
    func statsJson() -> String? { handle.statsJson() }
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
    func statsJson() -> String? { handle.statsJson() }
}
#endif

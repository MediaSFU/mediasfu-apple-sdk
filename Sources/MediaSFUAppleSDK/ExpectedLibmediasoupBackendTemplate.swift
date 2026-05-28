import Foundation

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC
#endif

public protocol MediaSFUExpectedLibmediasoupDeviceEngine {
    func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupSendTransportEngine
    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupRecvTransportEngine
}

public protocol MediaSFUExpectedLibmediasoupTransportEngine: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func setConnectionStateObserver(_ observer: ((String) -> Void)?)
}

public protocol MediaSFUExpectedLibmediasoupSendTransportEngine: MediaSFUExpectedLibmediasoupTransportEngine {
    func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?)
    func setProduceRequestHandler(_ handler: MediaSFUNativeProduceListener?)
    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend
}

public protocol MediaSFUExpectedLibmediasoupRecvTransportEngine: MediaSFUExpectedLibmediasoupTransportEngine {
    func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?)
    func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend
}

public final class MediaSFUExpectedLibmediasoupDeviceBackend: MediaSFURawLibmediasoupDeviceBackend {
    private let engine: MediaSFUExpectedLibmediasoupDeviceEngine

    public init(engine: MediaSFUExpectedLibmediasoupDeviceEngine) {
        self.engine = engine
    }

    public func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupSendTransportBackend {
        let transportEngine = try engine.createSendTransport(options: options)
        return MediaSFUExpectedLibmediasoupSendTransportBackend(engine: transportEngine)
    }

    public func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupRecvTransportBackend {
        let transportEngine = try engine.createRecvTransport(options: options)
        return MediaSFUExpectedLibmediasoupRecvTransportBackend(engine: transportEngine)
    }
}

public final class MediaSFUExpectedLibmediasoupSendTransportBackend: MediaSFURawLibmediasoupSendTransportBackend {
    private let engine: MediaSFUExpectedLibmediasoupSendTransportEngine
    private var connectListener: MediaSFUNativeConnectListener?
    private var produceListener: MediaSFUNativeProduceListener?
    private var stateListener: ((String) -> Void)?

    public init(engine: MediaSFUExpectedLibmediasoupSendTransportEngine) {
        self.engine = engine
        bindEngine()
    }

    public var id: String { engine.id }
    public var connectionState: String { engine.connectionState }
    public func close() { engine.close() }

    public func setConnectListener(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
        engine.setConnectRequestHandler(listener)
    }

    public func setConnectionStateListener(_ listener: ((String) -> Void)?) {
        stateListener = listener
        engine.setConnectionStateObserver(listener)
    }

    public func setProduceListener(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
        engine.setProduceRequestHandler(listener)
    }

    public func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend {
        try engine.produce(track: track, options: options)
    }

    private func bindEngine() {
        engine.setConnectRequestHandler(connectListener)
        engine.setProduceRequestHandler(produceListener)
        engine.setConnectionStateObserver(stateListener)
    }
}

public final class MediaSFUExpectedLibmediasoupRecvTransportBackend: MediaSFURawLibmediasoupRecvTransportBackend {
    private let engine: MediaSFUExpectedLibmediasoupRecvTransportEngine
    private var connectListener: MediaSFUNativeConnectListener?
    private var stateListener: ((String) -> Void)?

    public init(engine: MediaSFUExpectedLibmediasoupRecvTransportEngine) {
        self.engine = engine
        bindEngine()
    }

    public var id: String { engine.id }
    public var connectionState: String { engine.connectionState }
    public func close() { engine.close() }

    public func setConnectListener(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
        engine.setConnectRequestHandler(listener)
    }

    public func setConnectionStateListener(_ listener: ((String) -> Void)?) {
        stateListener = listener
        engine.setConnectionStateObserver(listener)
    }

    public func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend {
        try engine.consume(options: options)
    }

    private func bindEngine() {
        engine.setConnectRequestHandler(connectListener)
        engine.setConnectionStateObserver(stateListener)
    }
}
import Foundation

public protocol ConcreteMediasoupNativeDevice {
    func createSendTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeSendTransport
    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeRecvTransport
}

public protocol ConcreteMediasoupNativeTransport: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func setConnectionStateHandler(_ handler: ((String) -> Void)?)
}

public protocol ConcreteMediasoupNativeSendTransport: ConcreteMediasoupNativeTransport {
    func setConnectHandler(_ handler: MediaSFUNativeConnectListener?)
    func setProduceHandler(_ handler: MediaSFUNativeProduceListener?)
    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> ConcreteMediasoupNativeProducer
}

public protocol ConcreteMediasoupNativeRecvTransport: ConcreteMediasoupNativeTransport {
    func setConnectHandler(_ handler: MediaSFUNativeConnectListener?)
    func consume(options: MediaSFURawConsumeOptions) throws -> ConcreteMediasoupNativeConsumer
}

public protocol ConcreteMediasoupNativeProducer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack) throws
}

public protocol ConcreteMediasoupNativeConsumer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
}

public final class ConcreteMediasoupDeviceBinding: MediaSFUAssumedLibmediasoupDeviceBinding {
    private let nativeDevice: ConcreteMediasoupNativeDevice

    public init(nativeDevice: ConcreteMediasoupNativeDevice) {
        self.nativeDevice = nativeDevice
    }

    public func makeSendTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupSendTransportBinding {
        let transport = try nativeDevice.createSendTransport(options: config)
        return ConcreteMediasoupSendTransportBinding(nativeTransport: transport)
    }

    public func makeRecvTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupRecvTransportBinding {
        let transport = try nativeDevice.createRecvTransport(options: config)
        return ConcreteMediasoupRecvTransportBinding(nativeTransport: transport)
    }
}

public final class ConcreteMediasoupSendTransportBinding: MediaSFUAssumedLibmediasoupSendTransportBinding {
    private let nativeTransport: ConcreteMediasoupNativeSendTransport

    public init(nativeTransport: ConcreteMediasoupNativeSendTransport) {
        self.nativeTransport = nativeTransport
    }

    public var identifier: String { nativeTransport.id }
    public var state: String { nativeTransport.connectionState }
    public func shutdown() { nativeTransport.close() }
    public func observeState(_ observer: ((String) -> Void)?) { nativeTransport.setConnectionStateHandler(observer) }
    public func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?) { nativeTransport.setConnectHandler(handler) }
    public func onProduceNeeded(_ handler: MediaSFUNativeProduceListener?) { nativeTransport.setProduceHandler(handler) }

    public func startProducing(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFUAssumedLibmediasoupProducerBinding {
        let producer = try nativeTransport.produce(track: track, options: options)
        return ConcreteMediasoupProducerBinding(nativeProducer: producer)
    }
}

public final class ConcreteMediasoupRecvTransportBinding: MediaSFUAssumedLibmediasoupRecvTransportBinding {
    private let nativeTransport: ConcreteMediasoupNativeRecvTransport

    public init(nativeTransport: ConcreteMediasoupNativeRecvTransport) {
        self.nativeTransport = nativeTransport
    }

    public var identifier: String { nativeTransport.id }
    public var state: String { nativeTransport.connectionState }
    public func shutdown() { nativeTransport.close() }
    public func observeState(_ observer: ((String) -> Void)?) { nativeTransport.setConnectionStateHandler(observer) }
    public func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?) { nativeTransport.setConnectHandler(handler) }

    public func startConsuming(options: MediaSFURawConsumeOptions) throws -> MediaSFUAssumedLibmediasoupConsumerBinding {
        let consumer = try nativeTransport.consume(options: options)
        return ConcreteMediasoupConsumerBinding(nativeConsumer: consumer)
    }
}

public final class ConcreteMediasoupProducerBinding: MediaSFUAssumedLibmediasoupProducerBinding {
    private let nativeProducer: ConcreteMediasoupNativeProducer

    public init(nativeProducer: ConcreteMediasoupNativeProducer) {
        self.nativeProducer = nativeProducer
    }

    public var identifier: String { nativeProducer.id }
    public var mediaKind: String { nativeProducer.kind }
    public var isCurrentlyPaused: Bool { nativeProducer.paused }
    public func shutdown() { nativeProducer.close() }
    public func pauseSending() { nativeProducer.pause() }
    public func resumeSending() { nativeProducer.resume() }
    public func updateTrack(_ track: MediaSFUNativeTrack) throws { try nativeProducer.replaceTrack(track) }
}

public final class ConcreteMediasoupConsumerBinding: MediaSFUAssumedLibmediasoupConsumerBinding {
    private let nativeConsumer: ConcreteMediasoupNativeConsumer

    public init(nativeConsumer: ConcreteMediasoupNativeConsumer) {
        self.nativeConsumer = nativeConsumer
    }

    public var identifier: String { nativeConsumer.id }
    public var mediaKind: String { nativeConsumer.kind }
    public var mediaTrack: MediaSFUNativeTrack? { nativeConsumer.track }
    public var isCurrentlyPaused: Bool { nativeConsumer.paused }
    public func shutdown() { nativeConsumer.close() }
    public func pauseReceiving() { nativeConsumer.pause() }
    public func resumeReceiving() { nativeConsumer.resume() }
}

public enum ConcreteMediasoupBindingTemplate {
    public static func makeBinding(nativeDevice: ConcreteMediasoupNativeDevice) -> MediaSFUAssumedLibmediasoupDeviceBinding {
        ConcreteMediasoupDeviceBinding(nativeDevice: nativeDevice)
    }

    public static func makeInstallableAdapter(nativeDevice: ConcreteMediasoupNativeDevice) -> MediaSFUDeviceAdapter {
        RealMediasoupBindingEngine.makeInstallableAdapter(binding: makeBinding(nativeDevice: nativeDevice))
    }
}

// Implementation notes:
// - Conform a real iOS mediasoup wrapper to the ConcreteMediasoupNative* protocols.
// - Keep JSON payloads unchanged unless the library API requires conversion.
// - Route native onConnect / onProduce callbacks into the provided handlers.
// - Return WebRTC tracks from the same binary family used by the KMP framework.
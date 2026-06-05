import Foundation

public protocol MediaSFUAssumedLibmediasoupDeviceBinding {
    func makeSendTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupSendTransportBinding
    func makeRecvTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupRecvTransportBinding
}

public protocol MediaSFUAssumedLibmediasoupTransportBinding: AnyObject {
    var identifier: String { get }
    var state: String { get }
    func shutdown()
    func observeState(_ observer: ((String) -> Void)?)
}

public protocol MediaSFUAssumedLibmediasoupSendTransportBinding: MediaSFUAssumedLibmediasoupTransportBinding {
    func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?)
    func onProduceNeeded(_ handler: MediaSFUNativeProduceListener?)
    func startProducing(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFUAssumedLibmediasoupProducerBinding
}

public protocol MediaSFUAssumedLibmediasoupRecvTransportBinding: MediaSFUAssumedLibmediasoupTransportBinding {
    func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?)
    func startConsuming(options: MediaSFURawConsumeOptions) throws -> MediaSFUAssumedLibmediasoupConsumerBinding
}

public protocol MediaSFUAssumedLibmediasoupProducerBinding: AnyObject {
    var identifier: String { get }
    var mediaKind: String { get }
    var isCurrentlyPaused: Bool { get }
    func shutdown()
    func pauseSending()
    func resumeSending()
    func updateTrack(_ track: MediaSFUNativeTrack) throws
}

public protocol MediaSFUAssumedLibmediasoupConsumerBinding: AnyObject {
    var identifier: String { get }
    var mediaKind: String { get }
    var mediaTrack: MediaSFUNativeTrack? { get }
    var isCurrentlyPaused: Bool { get }
    func shutdown()
    func pauseReceiving()
    func resumeReceiving()
}

public final class MediaSFUAssumedLibmediasoupDeviceEngine: MediaSFUExpectedLibmediasoupDeviceEngine {
    private let binding: MediaSFUAssumedLibmediasoupDeviceBinding

    public init(binding: MediaSFUAssumedLibmediasoupDeviceBinding) {
        self.binding = binding
    }

    public func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupSendTransportEngine {
        let sendBinding = try binding.makeSendTransport(config: options)
        return MediaSFUAssumedLibmediasoupSendTransportEngine(binding: sendBinding)
    }

    public func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupRecvTransportEngine {
        let recvBinding = try binding.makeRecvTransport(config: options)
        return MediaSFUAssumedLibmediasoupRecvTransportEngine(binding: recvBinding)
    }
}

public final class MediaSFUAssumedLibmediasoupSendTransportEngine: MediaSFUExpectedLibmediasoupSendTransportEngine {
    private let binding: MediaSFUAssumedLibmediasoupSendTransportBinding

    public init(binding: MediaSFUAssumedLibmediasoupSendTransportBinding) {
        self.binding = binding
    }

    public var id: String { binding.identifier }
    public var connectionState: String { binding.state }
    public func close() { binding.shutdown() }
    public func setConnectionStateObserver(_ observer: ((String) -> Void)?) { binding.observeState(observer) }
    public func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?) { binding.onConnectNeeded(handler) }
    public func setProduceRequestHandler(_ handler: MediaSFUNativeProduceListener?) { binding.onProduceNeeded(handler) }

    public func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend {
        let producer = try binding.startProducing(track: track, options: options)
        return MediaSFUAssumedLibmediasoupProducerBackend(binding: producer)
    }
}

public final class MediaSFUAssumedLibmediasoupRecvTransportEngine: MediaSFUExpectedLibmediasoupRecvTransportEngine {
    private let binding: MediaSFUAssumedLibmediasoupRecvTransportBinding

    public init(binding: MediaSFUAssumedLibmediasoupRecvTransportBinding) {
        self.binding = binding
    }

    public var id: String { binding.identifier }
    public var connectionState: String { binding.state }
    public func close() { binding.shutdown() }
    public func setConnectionStateObserver(_ observer: ((String) -> Void)?) { binding.observeState(observer) }
    public func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?) { binding.onConnectNeeded(handler) }

    public func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend {
        let consumer = try binding.startConsuming(options: options)
        return MediaSFUAssumedLibmediasoupConsumerBackend(binding: consumer)
    }
}

public final class MediaSFUAssumedLibmediasoupProducerBackend: MediaSFURawLibmediasoupProducerBackend {
    private let binding: MediaSFUAssumedLibmediasoupProducerBinding

    public init(binding: MediaSFUAssumedLibmediasoupProducerBinding) {
        self.binding = binding
    }

    public var id: String { binding.identifier }
    public var kind: String { binding.mediaKind }
    public var paused: Bool { binding.isCurrentlyPaused }
    public func close() { binding.shutdown() }
    public func pause() { binding.pauseSending() }
    public func resume() { binding.resumeSending() }
    public func replaceTrack(_ track: MediaSFUNativeTrack) throws { try binding.updateTrack(track) }
}

public final class MediaSFUAssumedLibmediasoupConsumerBackend: MediaSFURawLibmediasoupConsumerBackend {
    private let binding: MediaSFUAssumedLibmediasoupConsumerBinding

    public init(binding: MediaSFUAssumedLibmediasoupConsumerBinding) {
        self.binding = binding
    }

    public var id: String { binding.identifier }
    public var kind: String { binding.mediaKind }
    public var track: MediaSFUNativeTrack? { binding.mediaTrack }
    public var paused: Bool { binding.isCurrentlyPaused }
    public func close() { binding.shutdown() }
    public func pause() { binding.pauseReceiving() }
    public func resume() { binding.resumeReceiving() }
}
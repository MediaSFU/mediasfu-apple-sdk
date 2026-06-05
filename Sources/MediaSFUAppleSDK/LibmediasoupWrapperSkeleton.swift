import Foundation

public protocol MediaSFURawLibmediasoupDeviceBackend {
    func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupSendTransportBackend
    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupRecvTransportBackend
}

public protocol MediaSFURawLibmediasoupTransportBackend: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func setConnectListener(_ listener: MediaSFUNativeConnectListener?)
    func setConnectionStateListener(_ listener: ((String) -> Void)?)
}

public protocol MediaSFURawLibmediasoupSendTransportBackend: MediaSFURawLibmediasoupTransportBackend {
    func setProduceListener(_ listener: MediaSFUNativeProduceListener?)
    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend
}

public protocol MediaSFURawLibmediasoupRecvTransportBackend: MediaSFURawLibmediasoupTransportBackend {
    func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend
}

public protocol MediaSFURawLibmediasoupProducerBackend: AnyObject {
    var id: String { get }
    var kind: String { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack) throws
}

public protocol MediaSFURawLibmediasoupConsumerBackend: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
}

public struct MediaSFURawTransportOptions: Equatable {
    public let id: String
    public let iceParametersJson: String
    public let iceCandidatesJson: String
    public let dtlsParametersJson: String
    public let sctpParametersJson: String?
    public let appDataJson: String?

    public init(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) {
        self.id = id
        self.iceParametersJson = iceParametersJson
        self.iceCandidatesJson = iceCandidatesJson
        self.dtlsParametersJson = dtlsParametersJson
        self.sctpParametersJson = sctpParametersJson
        self.appDataJson = appDataJson
    }
}

public struct MediaSFURawProduceOptions: Equatable {
    public let encodingsJson: String?
    public let codecOptionsJson: String?
    public let codecJson: String?
    public let appDataJson: String?

    public init(encodingsJson: String?, codecOptionsJson: String?, codecJson: String?, appDataJson: String?) {
        self.encodingsJson = encodingsJson
        self.codecOptionsJson = codecOptionsJson
        self.codecJson = codecJson
        self.appDataJson = appDataJson
    }
}

public struct MediaSFURawConsumeOptions: Equatable {
    public let id: String
    public let producerId: String
    public let kind: String
    public let rtpParametersJson: String

    public init(id: String, producerId: String, kind: String, rtpParametersJson: String) {
        self.id = id
        self.producerId = producerId
        self.kind = kind
        self.rtpParametersJson = rtpParametersJson
    }
}

public final class MediaSFULibmediasoupDeviceWrapper: MediaSFULibmediasoupDevice {
    private let backend: MediaSFURawLibmediasoupDeviceBackend

    public init(backend: MediaSFURawLibmediasoupDeviceBackend) {
        self.backend = backend
    }

    public func createSendTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupSendTransport {
        let backendTransport = try backend.createSendTransport(
            options: MediaSFURawTransportOptions(
                id: id,
                iceParametersJson: iceParametersJson,
                iceCandidatesJson: iceCandidatesJson,
                dtlsParametersJson: dtlsParametersJson,
                sctpParametersJson: sctpParametersJson,
                appDataJson: appDataJson
            )
        )
        return MediaSFULibmediasoupSendTransportWrapper(backend: backendTransport)
    }

    public func createRecvTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupRecvTransport {
        let backendTransport = try backend.createRecvTransport(
            options: MediaSFURawTransportOptions(
                id: id,
                iceParametersJson: iceParametersJson,
                iceCandidatesJson: iceCandidatesJson,
                dtlsParametersJson: dtlsParametersJson,
                sctpParametersJson: sctpParametersJson,
                appDataJson: appDataJson
            )
        )
        return MediaSFULibmediasoupRecvTransportWrapper(backend: backendTransport)
    }
}

public final class MediaSFULibmediasoupSendTransportWrapper: MediaSFULibmediasoupSendTransport {
    private let backend: MediaSFURawLibmediasoupSendTransportBackend

    public init(backend: MediaSFURawLibmediasoupSendTransportBackend) {
        self.backend = backend
    }

    public var id: String { backend.id }
    public var connectionState: String { backend.connectionState }
    public func close() { backend.close() }
    public func onConnect(_ listener: MediaSFUNativeConnectListener?) { backend.setConnectListener(listener) }
    public func onConnectionStateChange(_ listener: ((String) -> Void)?) { backend.setConnectionStateListener(listener) }
    public func onProduce(_ listener: MediaSFUNativeProduceListener?) { backend.setProduceListener(listener) }

    public func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupProducer {
        let producer = try backend.produce(
            track: track,
            options: MediaSFURawProduceOptions(
                encodingsJson: encodingsJson,
                codecOptionsJson: codecOptionsJson,
                codecJson: codecJson,
                appDataJson: appDataJson
            )
        )
        return MediaSFULibmediasoupProducerWrapper(backend: producer)
    }
}

public final class MediaSFULibmediasoupRecvTransportWrapper: MediaSFULibmediasoupRecvTransport {
    private let backend: MediaSFURawLibmediasoupRecvTransportBackend

    public init(backend: MediaSFURawLibmediasoupRecvTransportBackend) {
        self.backend = backend
    }

    public var id: String { backend.id }
    public var connectionState: String { backend.connectionState }
    public func close() { backend.close() }
    public func onConnect(_ listener: MediaSFUNativeConnectListener?) { backend.setConnectListener(listener) }
    public func onConnectionStateChange(_ listener: ((String) -> Void)?) { backend.setConnectionStateListener(listener) }

    public func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) throws -> MediaSFULibmediasoupConsumer {
        let consumer = try backend.consume(
            options: MediaSFURawConsumeOptions(
                id: id,
                producerId: producerId,
                kind: kind,
                rtpParametersJson: rtpParametersJson
            )
        )
        return MediaSFULibmediasoupConsumerWrapper(backend: consumer)
    }
}

public final class MediaSFULibmediasoupProducerWrapper: MediaSFULibmediasoupProducer {
    private let backend: MediaSFURawLibmediasoupProducerBackend

    public init(backend: MediaSFURawLibmediasoupProducerBackend) {
        self.backend = backend
    }

    public var id: String { backend.id }
    public var kind: String { backend.kind }
    public var paused: Bool { backend.paused }
    public func close() { backend.close() }
    public func pause() { backend.pause() }
    public func resume() { backend.resume() }
    public func replaceTrack(_ track: MediaSFUNativeTrack) throws { try backend.replaceTrack(track) }
}

public final class MediaSFULibmediasoupConsumerWrapper: MediaSFULibmediasoupConsumer {
    private let backend: MediaSFURawLibmediasoupConsumerBackend

    public init(backend: MediaSFURawLibmediasoupConsumerBackend) {
        self.backend = backend
    }

    public var id: String { backend.id }
    public var kind: String { backend.kind }
    public var track: MediaSFUNativeTrack? { backend.track }
    public var paused: Bool { backend.paused }
    public func close() { backend.close() }
    public func pause() { backend.pause() }
    public func resume() { backend.resume() }
}
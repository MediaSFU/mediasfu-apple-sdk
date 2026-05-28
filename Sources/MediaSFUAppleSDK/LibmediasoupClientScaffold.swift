import Foundation

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC
#endif

public protocol MediaSFULibmediasoupDevice {
    func createSendTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupSendTransport

    func createRecvTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupRecvTransport
}

public protocol MediaSFULibmediasoupTransport: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func onConnect(_ listener: MediaSFUNativeConnectListener?)
    func onConnectionStateChange(_ listener: ((String) -> Void)?)
}

public protocol MediaSFULibmediasoupSendTransport: MediaSFULibmediasoupTransport {
    func onProduce(_ listener: MediaSFUNativeProduceListener?)
    func produce(track: MediaSFUNativeTrack, encodingsJson: String?, appDataJson: String?) throws -> MediaSFULibmediasoupProducer
}

public protocol MediaSFULibmediasoupRecvTransport: MediaSFULibmediasoupTransport {
    func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) throws -> MediaSFULibmediasoupConsumer
}

public protocol MediaSFULibmediasoupProducer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack) throws
    func getStatsJson() -> String?
}

public protocol MediaSFULibmediasoupConsumer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func getStatsJson() -> String?
}

public final class LibmediasoupClientDeviceAdapter: MediaSFUDeviceAdapter {
    private let adapter: ClientBackedDeviceAdapter

    public init(device: MediaSFULibmediasoupDevice) {
        self.adapter = ClientBackedDeviceAdapter(clientDevice: LibmediasoupClientDevice(device: device))
    }

    public func createSendTransport(params: [String : Any?]) throws -> MediaSFUSendTransportAdapter {
        try adapter.createSendTransport(params: params)
    }

    public func createRecvTransport(params: [String : Any?]) throws -> MediaSFURecvTransportAdapter {
        try adapter.createRecvTransport(params: params)
    }
}

final class LibmediasoupClientDevice: MediaSFUNativeClientDevice {
    private let device: MediaSFULibmediasoupDevice

    init(device: MediaSFULibmediasoupDevice) {
        self.device = device
    }

    func createSendTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientSendTransport {
        let transport = try device.createSendTransport(
            id: options.id,
            iceParametersJson: options.iceParametersJson,
            iceCandidatesJson: options.iceCandidatesJson,
            dtlsParametersJson: options.dtlsParametersJson,
            sctpParametersJson: options.sctpParametersJson,
            appDataJson: options.appDataJson
        )
        return LibmediasoupClientSendTransport(transport: transport)
    }

    func createRecvTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientRecvTransport {
        let transport = try device.createRecvTransport(
            id: options.id,
            iceParametersJson: options.iceParametersJson,
            iceCandidatesJson: options.iceCandidatesJson,
            dtlsParametersJson: options.dtlsParametersJson,
            sctpParametersJson: options.sctpParametersJson,
            appDataJson: options.appDataJson
        )
        return LibmediasoupClientRecvTransport(transport: transport)
    }
}

final class LibmediasoupClientSendTransport: MediaSFUNativeClientSendTransport {
    private let transport: MediaSFULibmediasoupSendTransport

    init(transport: MediaSFULibmediasoupSendTransport) {
        self.transport = transport
    }

    var id: String { transport.id }
    var connectionState: String { transport.connectionState }
    func close() { transport.close() }
    func onConnect(_ listener: MediaSFUNativeConnectListener?) { transport.onConnect(listener) }
    func onConnectionStateChange(_ listener: ((String) -> Void)?) { transport.onConnectionStateChange(listener) }
    func onProduce(_ listener: MediaSFUNativeProduceListener?) { transport.onProduce(listener) }
    func produce(track: MediaSFUNativeTrack, options: MediaSFUProduceOptions) throws -> MediaSFUNativeClientProducer {
        let producer = try transport.produce(track: track, encodingsJson: options.encodingsJson, appDataJson: options.appDataJson)
        return LibmediasoupClientProducer(producer: producer)
    }
}

final class LibmediasoupClientRecvTransport: MediaSFUNativeClientRecvTransport {
    private let transport: MediaSFULibmediasoupRecvTransport

    init(transport: MediaSFULibmediasoupRecvTransport) {
        self.transport = transport
    }

    var id: String { transport.id }
    var connectionState: String { transport.connectionState }
    func close() { transport.close() }
    func onConnect(_ listener: MediaSFUNativeConnectListener?) { transport.onConnect(listener) }
    func onConnectionStateChange(_ listener: ((String) -> Void)?) { transport.onConnectionStateChange(listener) }
    func consume(options: MediaSFUConsumeOptions) throws -> MediaSFUNativeClientConsumer {
        let consumer = try transport.consume(
            id: options.id,
            producerId: options.producerId,
            kind: options.kind,
            rtpParametersJson: options.rtpParametersJson
        )
        return LibmediasoupClientConsumer(consumer: consumer)
    }
}

final class LibmediasoupClientProducer: MediaSFUNativeClientProducer {
    private let producer: MediaSFULibmediasoupProducer

    init(producer: MediaSFULibmediasoupProducer) {
        self.producer = producer
    }

    var id: String { producer.id }
    var kind: String { producer.kind }
    var paused: Bool { producer.paused }
    func close() { producer.close() }
    func pause() { producer.pause() }
    func resume() { producer.resume() }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws { try producer.replaceTrack(track) }
    func getStatsJson() -> String? { producer.getStatsJson() }
}

final class LibmediasoupClientConsumer: MediaSFUNativeClientConsumer {
    private let consumer: MediaSFULibmediasoupConsumer

    init(consumer: MediaSFULibmediasoupConsumer) {
        self.consumer = consumer
    }

    var id: String { consumer.id }
    var kind: String { consumer.kind }
    var track: MediaSFUNativeTrack? { consumer.track }
    var paused: Bool { consumer.paused }
    func close() { consumer.close() }
    func pause() { consumer.pause() }
    func resume() { consumer.resume() }
    func getStatsJson() -> String? { consumer.getStatsJson() }
}
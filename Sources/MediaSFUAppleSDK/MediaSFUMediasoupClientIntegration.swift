import Foundation

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient)
import MediaSFUMediasoupClient

public enum MediaSFUMediasoupClientBridgeFactory {
    public static func makeInstallableAdapter(device: MSCDevice) -> MediaSFUDeviceAdapter {
        let concreteDevice = MediaSFUMediasoupClientConcreteDevice(device: device)
        return ConcreteMediasoupBindingTemplate.makeInstallableAdapter(nativeDevice: concreteDevice)
    }
}

public final class MediaSFUMediasoupClientConcreteDevice: ConcreteMediasoupNativeDevice {
    private let device: MSCDevice

    public init(device: MSCDevice) {
        self.device = device
    }

    public func load(routerRtpCapabilitiesJson: String) throws {
        try device.load(routerRtpCapabilitiesJson: routerRtpCapabilitiesJson)
    }

    public func rtpCapabilitiesJson() throws -> String? {
        try device.rtpCapabilitiesJson()
    }

    public func createSendTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeSendTransport {
        let transport = try device.createSendTransport(
            id: options.id,
            iceParametersJson: options.iceParametersJson,
            iceCandidatesJson: options.iceCandidatesJson,
            dtlsParametersJson: options.dtlsParametersJson,
            sctpParametersJson: options.sctpParametersJson,
            appDataJson: options.appDataJson
        )
        return MediaSFUMediasoupClientConcreteSendTransport(transport: transport)
    }

    public func createRecvTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeRecvTransport {
        let transport = try device.createRecvTransport(
            id: options.id,
            iceParametersJson: options.iceParametersJson,
            iceCandidatesJson: options.iceCandidatesJson,
            dtlsParametersJson: options.dtlsParametersJson,
            sctpParametersJson: options.sctpParametersJson,
            appDataJson: options.appDataJson
        )
        return MediaSFUMediasoupClientConcreteRecvTransport(transport: transport)
    }
}

public final class MediaSFUMediasoupClientConcreteSendTransport: ConcreteMediasoupNativeSendTransport {
    private let transport: MSCSendTransport

    public init(transport: MSCSendTransport) {
        self.transport = transport
    }

    public var id: String { transport.id }
    public var connectionState: String { transport.connectionState }
    public func close() { transport.close() }
    public func setConnectionStateHandler(_ handler: ((String) -> Void)?) { transport.setConnectionStateHandler(handler) }
    public func setConnectHandler(_ handler: MediaSFUNativeConnectListener?) {
        transport.setConnectHandler(handler)
    }
    public func setProduceHandler(_ handler: MediaSFUNativeProduceListener?) {
        transport.setProduceHandler(handler)
    }

    public func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> ConcreteMediasoupNativeProducer {
        let producer = try transport.produce(
            track: track,
            encodingsJson: options.encodingsJson,
            appDataJson: options.appDataJson
        )
        return MediaSFUMediasoupClientConcreteProducer(producer: producer)
    }
}

public final class MediaSFUMediasoupClientConcreteRecvTransport: ConcreteMediasoupNativeRecvTransport {
    private let transport: MSCRecvTransport

    public init(transport: MSCRecvTransport) {
        self.transport = transport
    }

    public var id: String { transport.id }
    public var connectionState: String { transport.connectionState }
    public func close() { transport.close() }
    public func setConnectionStateHandler(_ handler: ((String) -> Void)?) { transport.setConnectionStateHandler(handler) }
    public func setConnectHandler(_ handler: MediaSFUNativeConnectListener?) {
        transport.setConnectHandler(handler)
    }

    public func consume(options: MediaSFURawConsumeOptions) throws -> ConcreteMediasoupNativeConsumer {
        let consumer = try transport.consume(
            id: options.id,
            producerId: options.producerId,
            kind: options.kind,
            rtpParametersJson: options.rtpParametersJson
        )
        return MediaSFUMediasoupClientConcreteConsumer(consumer: consumer)
    }
}

public final class MediaSFUMediasoupClientConcreteProducer: ConcreteMediasoupNativeProducer {
    private let producer: MSCProducer

    public init(producer: MSCProducer) {
        self.producer = producer
    }

    public var id: String { producer.id }
    public var kind: String { producer.kind }
    public var paused: Bool { producer.paused }
    public func close() { producer.close() }
    public func pause() { producer.pause() }
    public func resume() { producer.resume() }
    public func getStatsJson() -> String? { try? producer.getStatsJson() }

    public func replaceTrack(_ track: MediaSFUNativeTrack) throws {
        try producer.replaceTrack(track)
    }
}

public final class MediaSFUMediasoupClientConcreteConsumer: ConcreteMediasoupNativeConsumer {
    private let consumer: MSCConsumer

    public init(consumer: MSCConsumer) {
        self.consumer = consumer
    }

    public var id: String { consumer.id }
    public var kind: String { consumer.kind }
    public var track: MediaSFUNativeTrack? { consumer.track as? MediaSFUNativeTrack }
    public var paused: Bool { consumer.paused }
    public func close() { consumer.close() }
    public func pause() { consumer.pause() }
    public func resume() { consumer.resume() }
    public func getStatsJson() -> String? { try? consumer.getStatsJson() }
}
#endif

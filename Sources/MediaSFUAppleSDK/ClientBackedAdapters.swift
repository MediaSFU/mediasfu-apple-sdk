import Foundation

public struct MediaSFUTransportCreationOptions: Equatable {
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

    static func from(params: [String: Any?], kind: String) throws -> MediaSFUTransportCreationOptions {
        MediaSFUTransportCreationOptions(
            id: try requiredString(params, key: "id", context: "\(kind) transport id"),
            iceParametersJson: try requiredJson(params, key: "iceParameters", context: "\(kind) transport iceParameters"),
            iceCandidatesJson: try requiredJson(params, key: "iceCandidates", context: "\(kind) transport iceCandidates"),
            dtlsParametersJson: try requiredJson(params, key: "dtlsParameters", context: "\(kind) transport dtlsParameters"),
            sctpParametersJson: try optionalJson(params, key: "sctpParameters"),
            appDataJson: try optionalJson(params, key: "appData")
        )
    }
}

public struct MediaSFUProduceOptions: Equatable {
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

public struct MediaSFUConsumeOptions: Equatable {
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

public protocol MediaSFUNativeClientDevice {
    func createSendTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientSendTransport
    func createRecvTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientRecvTransport
}

public protocol MediaSFUNativeClientTransport: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func onConnect(_ listener: MediaSFUNativeConnectListener?)
    func onConnectionStateChange(_ listener: ((String) -> Void)?)
}

public protocol MediaSFUNativeClientSendTransport: MediaSFUNativeClientTransport {
    func onProduce(_ listener: MediaSFUNativeProduceListener?)
    func produce(track: MediaSFUNativeTrack, options: MediaSFUProduceOptions) throws -> MediaSFUNativeClientProducer
}

public protocol MediaSFUNativeClientRecvTransport: MediaSFUNativeClientTransport {
    func consume(options: MediaSFUConsumeOptions) throws -> MediaSFUNativeClientConsumer
}

public protocol MediaSFUNativeClientProducer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack) throws
}

public protocol MediaSFUNativeClientConsumer: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
}

public final class ClientBackedDeviceAdapter: MediaSFUDeviceAdapter {
    private let clientDevice: MediaSFUNativeClientDevice

    public init(clientDevice: MediaSFUNativeClientDevice) {
        self.clientDevice = clientDevice
    }

    public func createSendTransport(params: [String : Any?]) throws -> MediaSFUSendTransportAdapter {
        let options = try MediaSFUTransportCreationOptions.from(params: params, kind: "send")
        let transport = try clientDevice.createSendTransport(options: options)
        return ClientBackedSendTransportAdapter(transport: transport)
    }

    public func createRecvTransport(params: [String : Any?]) throws -> MediaSFURecvTransportAdapter {
        let options = try MediaSFUTransportCreationOptions.from(params: params, kind: "recv")
        let transport = try clientDevice.createRecvTransport(options: options)
        return ClientBackedRecvTransportAdapter(transport: transport)
    }
}

final class ClientBackedSendTransportAdapter: MediaSFUSendTransportAdapter {
    private let transport: MediaSFUNativeClientSendTransport

    init(transport: MediaSFUNativeClientSendTransport) {
        self.transport = transport
    }

    var id: String { transport.id }
    var connectionState: String { transport.connectionState }
    func close() { transport.close() }
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) { transport.onConnect(listener) }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) { transport.onConnectionStateChange(listener) }
    func setOnProduce(_ listener: MediaSFUNativeProduceListener?) { transport.onProduce(listener) }

    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) throws -> MediaSFUProducerAdapter {
        let producer = try transport.produce(
            track: track,
            options: MediaSFUProduceOptions(
                encodingsJson: encodingsJson,
                codecOptionsJson: codecOptionsJson,
                codecJson: codecJson,
                appDataJson: appDataJson
            )
        )
        return ClientBackedProducerAdapter(producer: producer)
    }
}

final class ClientBackedRecvTransportAdapter: MediaSFURecvTransportAdapter {
    private let transport: MediaSFUNativeClientRecvTransport

    init(transport: MediaSFUNativeClientRecvTransport) {
        self.transport = transport
    }

    var id: String { transport.id }
    var connectionState: String { transport.connectionState }
    func close() { transport.close() }
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) { transport.onConnect(listener) }
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) { transport.onConnectionStateChange(listener) }

    func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) throws -> MediaSFUConsumerAdapter {
        let consumer = try transport.consume(
            options: MediaSFUConsumeOptions(
                id: id,
                producerId: producerId,
                kind: kind,
                rtpParametersJson: rtpParametersJson
            )
        )
        return ClientBackedConsumerAdapter(consumer: consumer)
    }
}

final class ClientBackedProducerAdapter: MediaSFUProducerAdapter {
    private let producer: MediaSFUNativeClientProducer

    init(producer: MediaSFUNativeClientProducer) {
        self.producer = producer
    }

    var id: String { producer.id }
    var kind: String { producer.kind }
    var paused: Bool { producer.paused }
    func close() { producer.close() }
    func pause() { producer.pause() }
    func resume() { producer.resume() }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws { try producer.replaceTrack(track) }
}

final class ClientBackedConsumerAdapter: MediaSFUConsumerAdapter {
    private let consumer: MediaSFUNativeClientConsumer

    init(consumer: MediaSFUNativeClientConsumer) {
        self.consumer = consumer
    }

    var id: String { consumer.id }
    var kind: String { consumer.kind }
    var track: MediaSFUNativeTrack? { consumer.track }
    var paused: Bool { consumer.paused }
    func close() { consumer.close() }
    func pause() { consumer.pause() }
    func resume() { consumer.resume() }
    func getStatsJson() -> String? { return nil }
}

private func requiredString(_ params: [String: Any?], key: String, context: String) throws -> String {
    guard let value = params[key] as? String, !value.isEmpty else {
        throw MediaSFUBridgeError.invalidState("\(context) missing")
    }
    return value
}

private func requiredJson(_ params: [String: Any?], key: String, context: String) throws -> String {
    if let value = params[key] as? String, !value.isEmpty {
        return value
    }

    guard let raw = params[key], !(raw is NSNull) else {
        throw MediaSFUBridgeError.invalidState("\(context) missing")
    }

    return try MediaSFUBridgeJson.encode(raw)
}

private func optionalJson(_ params: [String: Any?], key: String) throws -> String? {
    if let value = params[key] as? String, !value.isEmpty {
        return value
    }

    guard let raw = params[key], !(raw is NSNull) else {
        return nil
    }

    return try MediaSFUBridgeJson.encode(raw)
}
import Foundation

public protocol MediaSFUDeviceAdapter {
    func createSendTransport(params: [String: Any?]) throws -> MediaSFUSendTransportAdapter
    func createRecvTransport(params: [String: Any?]) throws -> MediaSFURecvTransportAdapter
}

public protocol MediaSFULoadableDeviceAdapter: MediaSFUDeviceAdapter {
    func load(routerRtpCapabilitiesJson: String) throws
}

public protocol MediaSFUCurrentRtpCapabilitiesProvider {
    func currentRtpCapabilitiesJson() -> String?
}

public protocol MediaSFUTransportAdapter: AnyObject {
    var id: String { get }
    var connectionState: String { get }
    func close()
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?)
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?)
}

public protocol MediaSFUSendTransportAdapter: MediaSFUTransportAdapter {
    func setOnProduce(_ listener: MediaSFUNativeProduceListener?)
    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) throws -> MediaSFUProducerAdapter
}

public protocol MediaSFURecvTransportAdapter: MediaSFUTransportAdapter {
    func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) throws -> MediaSFUConsumerAdapter
}

public protocol MediaSFUProducerAdapter: AnyObject {
    var id: String { get }
    var kind: String { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack) throws
}

public protocol MediaSFUConsumerAdapter: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    var paused: Bool { get }
    func close()
    func pause()
    func resume()
    func getStatsJson() -> String?
}
import Foundation

#if canImport(WebRTC)
import WebRTC
public typealias MediaSFUNativeTrack = RTCMediaStreamTrack
#else
public protocol MediaSFUNativeTrack: AnyObject {}
#endif

public protocol MediaSFUNativeMediasoupBridge {
    func createSendTransport(params: [String: Any?]) -> MediaSFUNativeSendTransportHandle
    func createRecvTransport(params: [String: Any?]) -> MediaSFUNativeRecvTransportHandle
}

public protocol MediaSFUNativeTransportHandle: AnyObject {
    var id: String { get }
    func connectionState() -> String
    func close()
    func setOnConnect(_ listener: MediaSFUNativeConnectListener?)
    func setOnConnectionStateChange(_ listener: ((String) -> Void)?)
}

public protocol MediaSFUNativeSendTransportHandle: MediaSFUNativeTransportHandle {
    func setOnProduce(_ listener: MediaSFUNativeProduceListener?)
    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) -> MediaSFUNativeProducerHandle
}

public protocol MediaSFUNativeRecvTransportHandle: MediaSFUNativeTransportHandle {
    func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) -> MediaSFUNativeConsumerHandle
}

public protocol MediaSFUNativeProducerHandle: AnyObject {
    var id: String { get }
    var kind: String { get }
    func isPaused() -> Bool
    func close()
    func pause()
    func resume()
    func replaceTrack(_ track: MediaSFUNativeTrack)
    func statsJson() -> String?
}

public protocol MediaSFUNativeConsumerHandle: AnyObject {
    var id: String { get }
    var kind: String { get }
    var track: MediaSFUNativeTrack? { get }
    func isPaused() -> Bool
    func close()
    func pause()
    func resume()
    func statsJson() -> String?
}

public protocol MediaSFUNativeLoadableMediasoupBridge: MediaSFUNativeMediasoupBridge {
    func load(routerRtpCapabilitiesJson: String) throws
    func currentRtpCapabilitiesJson() -> String?
}

public typealias MediaSFUNativeConnectListener = (
    _ dtlsParametersJson: String,
    _ callback: @escaping () -> Void,
    _ errback: @escaping (Error) -> Void
) -> Void

public typealias MediaSFUNativeProduceListener = (
    _ kind: String,
    _ rtpParametersJson: String,
    _ appDataJson: String?,
    _ callback: @escaping (String?) -> Void,
    _ errback: @escaping (Error) -> Void
) -> Void

import Foundation

public final class PlaceholderMediasoupBridge: MediaSFUNativeMediasoupBridge {
    public init() {}

    public func createSendTransport(params: [String: Any?]) -> MediaSFUNativeSendTransportHandle {
        PlaceholderSendTransportHandle(id: "send-placeholder", params: params)
    }

    public func createRecvTransport(params: [String: Any?]) -> MediaSFUNativeRecvTransportHandle {
        PlaceholderRecvTransportHandle(id: "recv-placeholder", params: params)
    }
}

open class PlaceholderTransportHandle {
    public let id: String
    public let params: [String: Any?]
    public var connectListener: MediaSFUNativeConnectListener?
    public var stateListener: ((String) -> Void)?
    public private(set) var state: String

    public init(id: String, params: [String: Any?], state: String = "new") {
        self.id = id
        self.params = params
        self.state = state
    }

    open func connectionState() -> String {
        state
    }

    open func close() {
        state = "closed"
        stateListener?(state)
    }

    open func setOnConnect(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
    }

    open func setOnConnectionStateChange(_ listener: ((String) -> Void)?) {
        stateListener = listener
    }

    public func updateState(_ newState: String) {
        state = newState
        stateListener?(newState)
    }

    public func triggerOnConnect(
        dtlsParameters: [String: Any?],
        onCallback: (() -> Void)? = nil,
        onErrback: ((Error) -> Void)? = nil
    ) throws {
        let json = try MediaSFUBridgeJson.encode(dtlsParameters)
        connectListener?(
            json,
            { onCallback?() },
            { error in onErrback?(error) }
        )
    }

    public func triggerOnConnectError(
        _ error: Error = MediaSFUBridgeError.connectFailed("placeholder connect failure"),
        onErrback: ((Error) -> Void)? = nil
    ) {
        connectListener?(
            "{}",
            {},
            { callbackError in
                onErrback?(callbackError)
            }
        )
        onErrback?(error)
    }
}

public final class PlaceholderSendTransportHandle: PlaceholderTransportHandle, MediaSFUNativeSendTransportHandle {
    public var produceListener: MediaSFUNativeProduceListener?
    public private(set) var lastEncodingsJson: String?
    public private(set) var lastCodecOptionsJson: String?
    public private(set) var lastCodecJson: String?
    public private(set) var lastAppDataJson: String?
    public private(set) var producedHandle: PlaceholderProducerHandle?

    public func setOnProduce(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
    }

    public func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        codecOptionsJson: String?,
        codecJson: String?,
        appDataJson: String?
    ) -> MediaSFUNativeProducerHandle {
        lastEncodingsJson = encodingsJson
        lastCodecOptionsJson = codecOptionsJson
        lastCodecJson = codecJson
        lastAppDataJson = appDataJson
        let handle = PlaceholderProducerHandle(id: UUID().uuidString, kind: inferredKind(from: track))
        producedHandle = handle
        return handle
    }

    public func triggerOnProduce(
        kind: String,
        rtpParameters: [String: Any?],
        appData: [String: Any?]? = nil,
        producerId: String = UUID().uuidString,
        onCallback: ((String?) -> Void)? = nil,
        onErrback: ((Error) -> Void)? = nil
    ) throws {
        let rtpJson = try MediaSFUBridgeJson.encode(rtpParameters)
        let appDataJson = try appData.map { try MediaSFUBridgeJson.encode($0) }
        produceListener?(
            kind,
            rtpJson,
            appDataJson,
            { value in onCallback?(value ?? producerId) },
            { error in onErrback?(error) }
        )
    }

    public func triggerOnProduceError(
        _ error: Error = MediaSFUBridgeError.produceFailed("placeholder produce failure"),
        onErrback: ((Error) -> Void)? = nil
    ) {
        produceListener?(
            "audio",
            "{}",
            nil,
            { _ in },
            { callbackError in
                onErrback?(callbackError)
            }
        )
        onErrback?(error)
    }

    private func inferredKind(from track: MediaSFUNativeTrack) -> String {
        #if canImport(WebRTC)
        return track.kind
        #else
        return "audio"
        #endif
    }
}

public final class PlaceholderRecvTransportHandle: PlaceholderTransportHandle, MediaSFUNativeRecvTransportHandle {
    public private(set) var lastConsumerId: String?
    public private(set) var lastProducerId: String?
    public private(set) var lastConsumerKind: String?
    public private(set) var lastRtpParametersJson: String?

    public func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) -> MediaSFUNativeConsumerHandle {
        lastConsumerId = id
        lastProducerId = producerId
        lastConsumerKind = kind
        lastRtpParametersJson = rtpParametersJson
        return PlaceholderConsumerHandle(id: id, kind: kind, track: nil)
    }

    public func decodedLastRtpParameters() throws -> [String: Any] {
        guard let lastRtpParametersJson else {
            throw MediaSFUBridgeError.consumeFailed("No RTP parameters captured")
        }
        return try MediaSFUBridgeJson.decodeObject(lastRtpParametersJson)
    }
}

public final class PlaceholderProducerHandle: MediaSFUNativeProducerHandle {
    public let id: String
    public let kind: String
    private var paused = false

    public init(id: String, kind: String) {
        self.id = id
        self.kind = kind
    }

    public func isPaused() -> Bool {
        paused
    }

    public func close() {}

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
    }

    public func replaceTrack(_ track: MediaSFUNativeTrack) {}
    public func statsJson() -> String? { nil }
}

public final class PlaceholderConsumerHandle: MediaSFUNativeConsumerHandle {
    public let id: String
    public let kind: String
    public let track: MediaSFUNativeTrack?
    private var paused = false

    public init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    public func isPaused() -> Bool {
        paused
    }

    public func close() {}

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
    }
    public func statsJson() -> String? { nil }
}

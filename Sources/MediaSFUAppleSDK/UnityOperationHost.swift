import Dispatch
import Foundation

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC
#endif

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
private struct MediaSFUUnityRemoteVideoFrameSnapshot {
    let sequence: Int64
    let width: Int
    let height: Int
    let rotation: Int
    let timestampNs: Int64
    let byteCount: Int
    let bgraBytes: Data
}

private final class MediaSFUUnityRemoteVideoFrameRenderer: NSObject, RTCVideoRenderer {
    private let frameLock = NSLock()
    private var latestFrame: MediaSFUUnityRemoteVideoFrameSnapshot?
    private var nextSequence: Int64 = 1

    func setSize(_ size: CGSize) {
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let snapshot = makeSnapshot(from: frame) else {
            return
        }

        frameLock.lock()
        latestFrame = snapshot
        frameLock.unlock()
    }

    func metadataDictionary() -> [String: Any]? {
        frameLock.lock()
        let snapshot = latestFrame
        frameLock.unlock()

        guard let snapshot else {
            return nil
        }

        return [
            "available": true,
            "sequence": snapshot.sequence,
            "width": snapshot.width,
            "height": snapshot.height,
            "rotation": snapshot.rotation,
            "timestampNs": snapshot.timestampNs,
            "byteCount": snapshot.byteCount,
        ]
    }

    func copyLatestFrame(to destination: UnsafeMutableRawPointer, capacity: Int) -> Int {
        frameLock.lock()
        let snapshot = latestFrame
        frameLock.unlock()

        guard let snapshot else {
            return 0
        }

        guard capacity >= snapshot.byteCount else {
            return -snapshot.byteCount
        }

        snapshot.bgraBytes.copyBytes(
            to: destination.assumingMemoryBound(to: UInt8.self),
            count: snapshot.byteCount
        )
        return snapshot.byteCount
    }

    private func makeSnapshot(from frame: RTCVideoFrame) -> MediaSFUUnityRemoteVideoFrameSnapshot? {
        let i420Buffer = frame.buffer.toI420()
        let width = Int(i420Buffer.width)
        let height = Int(i420Buffer.height)
        guard width > 0, height > 0 else {
            return nil
        }

        var bgraBytes = Data(count: width * height * 4)
        let didConvert = bgraBytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let destination = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }

            Self.convertI420ToBGRA(
                buffer: i420Buffer,
                width: width,
                height: height,
                destination: destination
            )
            return true
        }

        guard didConvert else {
            return nil
        }

        frameLock.lock()
        let sequence = nextSequence
        nextSequence += 1
        frameLock.unlock()

        return MediaSFUUnityRemoteVideoFrameSnapshot(
            sequence: sequence,
            width: width,
            height: height,
            rotation: frame.rotation.rawValue,
            timestampNs: frame.timeStampNs,
            byteCount: bgraBytes.count,
            bgraBytes: bgraBytes
        )
    }

    private static func convertI420ToBGRA(
        buffer: any RTCI420BufferProtocol,
        width: Int,
        height: Int,
        destination: UnsafeMutablePointer<UInt8>
    ) {
        let strideY = Int(buffer.strideY)
        let strideU = Int(buffer.strideU)
        let strideV = Int(buffer.strideV)

        for row in 0..<height {
            let yRow = buffer.dataY.advanced(by: row * strideY)
            let uRow = buffer.dataU.advanced(by: (row / 2) * strideU)
            let vRow = buffer.dataV.advanced(by: (row / 2) * strideV)

            for column in 0..<width {
                let yValue = Int(yRow[column])
                let uValue = Int(uRow[column / 2])
                let vValue = Int(vRow[column / 2])

                let c = max(yValue - 16, 0)
                let d = uValue - 128
                let e = vValue - 128

                let red = clampColor((298 * c + 409 * e + 128) >> 8)
                let green = clampColor((298 * c - 100 * d - 208 * e + 128) >> 8)
                let blue = clampColor((298 * c + 516 * d + 128) >> 8)

                let pixelOffset = (row * width + column) * 4
                destination[pixelOffset] = blue
                destination[pixelOffset + 1] = green
                destination[pixelOffset + 2] = red
                destination[pixelOffset + 3] = 255
            }
        }
    }

    private static func clampColor(_ value: Int) -> UInt8 {
        UInt8(min(max(value, 0), 255))
    }
}
#endif

public enum MediaSFUUnityTrackKind: Int {
    case audio = 0
    case video = 1
    case screen = 2
    case whiteboard = 3

    var mediaTag: String {
        switch self {
        case .audio:
            return "audio"
        case .video:
            return "video"
        case .screen:
            return "screen"
        case .whiteboard:
            return "whiteboard"
        }
    }

    var expectedNativeKind: String {
        switch self {
        case .audio:
            return "audio"
        case .video, .screen, .whiteboard:
            return "video"
        }
    }
}

public final class MediaSFUUnityLocalTrackResource {
    public let track: MediaSFUNativeTrack

    private let onDispose: () -> Void
    private let disposeLock = NSLock()
    private var disposed = false

    public init(track: MediaSFUNativeTrack, onDispose: @escaping () -> Void = {}) {
        self.track = track
        self.onDispose = onDispose
    }

    public func dispose() {
        disposeLock.lock()
        let shouldDispose = !disposed
        disposed = true
        disposeLock.unlock()

        if shouldDispose {
            onDispose()
        }
    }
}

public final class MediaSFUIosUnityWebRtcOperationHost {
    public typealias LocalTrackFactory = (MediaSFUUnityTrackKind) throws -> MediaSFUUnityLocalTrackResource

    private let device: MediaSFUDeviceAdapter
    private let trackFactory: LocalTrackFactory
    private let connectEventTimeout: TimeInterval
    private let produceEventTimeout: TimeInterval
    private let produceQueue = DispatchQueue(label: "com.mediasfu.ios.unity.operation-host.produce")
    private let stateLock = NSLock()

    private var loadedCapabilitiesCanonicalJson: String?
    private var sendTransportState: PendingSendTransportState?
    private var receiveTransportStates: [String: PendingReceiveTransportState] = [:]

    public init(
        device: MediaSFUDeviceAdapter,
        connectEventTimeout: TimeInterval = 5.0,
        produceEventTimeout: TimeInterval = 5.0,
        trackFactory: LocalTrackFactory? = nil
    ) {
        self.device = device
        self.connectEventTimeout = connectEventTimeout
        self.produceEventTimeout = produceEventTimeout
        self.trackFactory = trackFactory ?? Self.unsupportedTrackFactory()
    }

    public convenience init(
        clientDevice: MediaSFUNativeClientDevice,
        connectEventTimeout: TimeInterval = 5.0,
        produceEventTimeout: TimeInterval = 5.0,
        trackFactory: LocalTrackFactory? = nil
    ) {
        self.init(
            device: ClientBackedDeviceAdapter(clientDevice: clientDevice),
            connectEventTimeout: connectEventTimeout,
            produceEventTimeout: produceEventTimeout,
            trackFactory: trackFactory
        )
    }

    public func invoke(operationName: String, payloadJson: String = "") -> String {
        switch operationName {
        case OperationNames.describeBackend:
            return invokeJsonOperation {
                describeBackend()
            }

        case OperationNames.loadDeviceRtpCapabilities:
            return invokeVoidOperation {
                try loadDeviceRtpCapabilities(payloadJson: payloadJson)
            }

        case OperationNames.initializeSendTransport:
            return invokeVoidOperation {
                try initializeSendTransport(payloadJson: payloadJson)
            }

        case OperationNames.createSendTransportConnectParameters:
            return invokeJsonOperation {
                try createSendTransportConnectParameters()
            }

        case OperationNames.completeSendTransportConnect:
            return invokeVoidOperation {
                try completeSendTransportConnect(payloadJson: payloadJson)
            }

        case OperationNames.createProduceRequest:
            return invokeJsonOperation {
                try createProduceRequest(payloadJson: payloadJson)
            }

        case OperationNames.bindProducer:
            return invokeVoidOperation {
                try bindProducer(payloadJson: payloadJson)
            }

        case OperationNames.pauseProducer:
            return invokeVoidOperation {
                try pauseProducer(payloadJson: payloadJson)
            }

        case OperationNames.resumeProducer:
            return invokeVoidOperation {
                try resumeProducer(payloadJson: payloadJson)
            }

        case OperationNames.closeProducer:
            return invokeVoidOperation {
                try closeProducer(payloadJson: payloadJson)
            }

        case OperationNames.initializeReceiveTransport:
            return invokeVoidOperation {
                try initializeReceiveTransport(payloadJson: payloadJson)
            }

        case OperationNames.createReceiveTransportConnectParameters:
            return invokeJsonOperation {
                try createReceiveTransportConnectParameters(payloadJson: payloadJson)
            }

        case OperationNames.completeReceiveTransportConnect:
            return invokeVoidOperation {
                try completeReceiveTransportConnect(payloadJson: payloadJson)
            }

        case OperationNames.bindConsumer:
            return invokeVoidOperation {
                try bindConsumer(payloadJson: payloadJson)
            }

        case OperationNames.getRemoteVideoFrameMetadata:
            return invokeJsonOperation {
                try getRemoteVideoFrameMetadata(payloadJson: payloadJson)
            }

        case OperationNames.closeConsumer:
            return invokeVoidOperation {
                try closeConsumer(payloadJson: payloadJson)
            }

        default:
            return unknownOperationResponse(operationName: operationName)
        }
    }

    public func describe() -> String {
        "\(currentPlatformDisplayName()) Unity WebRTC operation host backed by \(String(describing: type(of: device)))"
    }

    public func copyRemoteVideoFrame(
        remoteProducerId: String,
        destination: UnsafeMutableRawPointer?,
        capacity: Int
    ) -> Int {
        guard let destination, capacity > 0 else {
            return 0
        }

    #if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
        let renderer = withStateLock {
            resolveReceiveTransportState(forFrameLookupId: remoteProducerId)?.state.videoRenderer
        }

        return renderer?.copyLatestFrame(to: destination, capacity: capacity) ?? 0
    #else
        _ = remoteProducerId
        return 0
    #endif
    }

    private func describeBackend() -> [String: Any] {
#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC) && canImport(AVFoundation)
        let supportsAudio = true
        let supportsVideo = true
#if os(macOS)
    let supportsScreenShare = true
#else
        let supportsScreenShare = false
#endif
        let supportsWhiteboard = false
        let supportsReceive = true
#else
        let supportsAudio = false
        let supportsVideo = false
        let supportsScreenShare = false
        let supportsWhiteboard = false
        let supportsReceive = false
#endif

        return [
            "description": describe(),
            "backendKind": "installed",
            "isPlaceholder": false,
            "platform": currentPlatformIdentifier(),
            "supportsAudio": supportsAudio,
            "supportsVideo": supportsVideo,
            "supportsScreenShare": supportsScreenShare,
            "supportsWhiteboard": supportsWhiteboard,
            "supportsReceive": supportsReceive
        ]
    }

    private func currentPlatformIdentifier() -> String {
#if os(macOS)
        return "macos"
#else
        return "ios"
#endif
    }

    private func currentPlatformDisplayName() -> String {
#if os(macOS)
        return "macOS"
#else
        return "iOS"
#endif
    }

    private func loadDeviceRtpCapabilities(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.loadDeviceRtpCapabilities)
        let roomRtpCapabilitiesJson = try requiredNonEmptyString(
            payload,
            key: "roomRtpCapabilitiesJson",
            message: "loadDeviceRtpCapabilities requires a non-empty roomRtpCapabilitiesJson payload."
        )
        let canonicalJson = try canonicalizeJson(roomRtpCapabilitiesJson)

        let loadedCapabilities = withStateLock { loadedCapabilitiesCanonicalJson }
        if loadedCapabilities == canonicalJson {
            return
        }

        if let loadedCapabilities, loadedCapabilities != canonicalJson {
            throw MediaSFUUnityOperationError(
                "MediaSFUIosUnityWebRtcOperationHost cannot reload different router RTP capabilities on the same backend instance."
            )
        }

        if let loadableDevice = device as? MediaSFULoadableDeviceAdapter {
            try loadableDevice.load(routerRtpCapabilitiesJson: roomRtpCapabilitiesJson)
        }

        withStateLock {
            loadedCapabilitiesCanonicalJson = canonicalJson
        }
    }

    private func initializeSendTransport(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.initializeSendTransport)
        let transport = try parseTransportPayload(payload, operationName: OperationNames.initializeSendTransport)
        let previousState = withStateLock { () -> PendingSendTransportState? in
            let state = sendTransportState
            sendTransportState = nil
            return state
        }
        previousState?.close(reason: "initializeSendTransport replaced the existing transport.")

        let nextState = PendingSendTransportState(
            transportId: transport.id,
            transport: try device.createSendTransport(params: try buildTransportParams(
                transport,
                operationName: OperationNames.initializeSendTransport
            ))
        )

        nextState.transport.setOnConnect { [weak nextState] dtlsParametersJson, callback, errback in
            guard let nextState else { return }
            let connectData = PendingConnectData(
                dtlsParametersJson: self.canonicalizeJsonIfPossible(dtlsParametersJson),
                callback: callback,
                errback: errback
            )

            self.withStateLock {
                nextState.activeConnectData = connectData
            }
            nextState.pendingConnectData.resolve(connectData)
        }

        nextState.transport.setOnConnectionStateChange { [weak nextState] state in
            guard let nextState else { return }
            guard self.isTerminalTransportState(state) else {
                return
            }

            nextState.pendingConnectData.reject(
                MediaSFUUnityOperationError(
                    "Send transport \(nextState.transportId) entered \(state) before connect completion."
                )
            )
        }

        nextState.transport.setOnProduce { [weak nextState] kind, rtpParametersJson, appDataJson, callback, errback in
            guard nextState != nil else { return }

            do {
                let trackKind = try self.resolveTrackKind(kind: kind, appDataJson: appDataJson)
                let pendingProduceState = try self.withStateLock { () throws -> PendingProduceState in
                    guard let state = self.sendTransportState else {
                        throw MediaSFUUnityOperationError(
                            "bindProducer requires initializeSendTransport to succeed first."
                        )
                    }

                    guard let pendingState = state.pendingProduceStates[trackKind] else {
                        throw MediaSFUUnityOperationError(
                            "createProduceRequest could not find pending produce callback data for \(trackKind.mediaTag)."
                        )
                    }

                    return pendingState
                }

                let produceData = PendingProduceData(
                    kind: kind.isEmpty ? trackKind.expectedNativeKind : kind,
                    rtpParametersJson: self.canonicalizeJsonIfPossible(rtpParametersJson),
                    appDataJson: appDataJson,
                    callback: callback,
                    errback: errback
                )

                self.withStateLock {
                    pendingProduceState.activeProduceData = produceData
                }
                pendingProduceState.produceData.resolve(produceData)
            } catch {
                errback(error)
            }
        }

        withStateLock {
            sendTransportState = nextState
        }
    }

    private func createSendTransportConnectParameters() throws -> Any {
        let state = try requireSendTransportState(operationName: OperationNames.createSendTransportConnectParameters)
        let connectData = try resolveSendConnectData(
            state,
            operationName: OperationNames.createSendTransportConnectParameters
        )

        return [
            "dtlsParametersJson": connectData.dtlsParametersJson
        ]
    }

    private func completeSendTransportConnect(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.completeSendTransportConnect)
        let state = try requireSendTransportState(operationName: OperationNames.completeSendTransportConnect)
        let connectData = try resolveSendConnectData(
            state,
            operationName: OperationNames.completeSendTransportConnect
        )

        withStateLock {
            state.activeConnectData = nil
        }

        if boolValue(payload, key: "success") {
            connectData.callback()
            return
        }

        let detail = optionalString(payload, key: "errorDetail").takeUnlessBlank()
            ?? "Send transport connect failed."
        connectData.errback(MediaSFUUnityOperationError(detail))
    }

    private func createProduceRequest(payloadJson: String) throws -> Any {
        let payload = try parseCreateProduceRequestPayload(payloadJson)
        let state = try requireSendTransportState(operationName: OperationNames.createProduceRequest)

        let pendingProduceState = try withStateLock { () throws -> PendingProduceState in
            if state.activeProducers[payload.trackKind] != nil {
                throw MediaSFUUnityOperationError(
                    "createProduceRequest cannot start a second \(payload.trackKind.mediaTag) producer while one is already active."
                )
            }

            if state.pendingProduceStates[payload.trackKind] != nil {
                throw MediaSFUUnityOperationError(
                    "createProduceRequest already has a pending \(payload.trackKind.mediaTag) producer handshake."
                )
            }

            let trackResource = try trackFactory(payload.trackKind)
            let pendingState = PendingProduceState(
                trackKind: payload.trackKind,
                participantName: payload.participantName.takeUnlessBlank() ?? payload.localUserName,
                participantIsLevel: payload.participantIsLevel.takeUnlessBlank() ?? payload.localIsLevel,
                trackResource: trackResource
            )
            state.pendingProduceStates[payload.trackKind] = pendingState
            return pendingState
        }

        produceQueue.async { [weak self, weak state] in
            guard let self, let state else {
                pendingProduceState.trackResource.dispose()
                pendingProduceState.produceData.reject(
                    MediaSFUUnityOperationError("MediaSFU iOS Unity operation host was released before producer creation finished.")
                )
                pendingProduceState.producerReady.reject(
                    MediaSFUUnityOperationError("MediaSFU iOS Unity operation host was released before producer creation finished.")
                )
                return
            }

            do {
                let producer = try state.transport.produce(
                    track: pendingProduceState.trackResource.track,
                    encodingsJson: nil,
                    codecOptionsJson: nil,
                    codecJson: nil,
                    appDataJson: try self.buildProduceAppDataJson(trackKind: payload.trackKind)
                )

                self.withStateLock {
                    state.pendingProduceStates.removeValue(forKey: payload.trackKind)
                    state.activeProducers[payload.trackKind] = ActiveProducerState(
                        producer: producer,
                        trackResource: pendingProduceState.trackResource
                    )
                }
                pendingProduceState.producerReady.resolve(producer)
            } catch {
                _ = self.withStateLock {
                    state.pendingProduceStates.removeValue(forKey: payload.trackKind)
                }
                pendingProduceState.trackResource.dispose()
                pendingProduceState.produceData.reject(error)
                pendingProduceState.producerReady.reject(error)
            }
        }

        let produceData = try pendingProduceState.produceData.await(
            timeout: produceEventTimeout,
            timeoutMessage: "createProduceRequest timed out waiting for iOS mediasoup produce parameters for \(payload.trackKind.mediaTag)."
        )

        withStateLock {
            pendingProduceState.activeProduceData = produceData
        }

        return [
            "produceRequest": [
                "kind": produceData.kind.isEmpty ? payload.trackKind.expectedNativeKind : produceData.kind,
                "rtpParametersJson": produceData.rtpParametersJson,
                "appDataJson": produceData.appDataJson ?? "",
                "name": pendingProduceState.participantName,
                "isLevel": pendingProduceState.participantIsLevel
            ]
        ]
    }

    private func bindProducer(payloadJson: String) throws {
        let payload = try parseBindProducerPayload(payloadJson)
        let state = try requireSendTransportState(operationName: OperationNames.bindProducer)
        let pendingProduceState = try withStateLock { () throws -> PendingProduceState in
            guard let pendingState = state.pendingProduceStates[payload.trackKind] else {
                throw MediaSFUUnityOperationError(
                    "bindProducer requires an in-flight \(payload.trackKind.mediaTag) produce handshake."
                )
            }
            return pendingState
        }

        let produceData: PendingProduceData
        if let activeProduceData = pendingProduceState.activeProduceData {
            produceData = activeProduceData
        } else {
            produceData = try pendingProduceState.produceData.await(
                timeout: produceEventTimeout,
                timeoutMessage: "bindProducer could not find pending produce callback data for \(payload.trackKind.mediaTag)."
            )
        }

        produceData.callback(payload.producerId)
        _ = try pendingProduceState.producerReady.await(
            timeout: produceEventTimeout,
            timeoutMessage: "bindProducer timed out waiting for iOS mediasoup producer creation for \(payload.trackKind.mediaTag)."
        )
    }

    private func pauseProducer(payloadJson: String) throws {
        let trackKind = try parseTrackOperationPayload(
            payloadJson,
            operationName: OperationNames.pauseProducer
        )
        try requireActiveProducerState(trackKind: trackKind, operationName: OperationNames.pauseProducer)
            .producer.pause()
    }

    private func resumeProducer(payloadJson: String) throws {
        let trackKind = try parseTrackOperationPayload(
            payloadJson,
            operationName: OperationNames.resumeProducer
        )
        try requireActiveProducerState(trackKind: trackKind, operationName: OperationNames.resumeProducer)
            .producer.resume()
    }

    private func closeProducer(payloadJson: String) throws {
        let trackKind = try parseTrackOperationPayload(
            payloadJson,
            operationName: OperationNames.closeProducer
        )
        let activeState = try withStateLock { () throws -> ActiveProducerState in
            guard let sendState = sendTransportState else {
                throw MediaSFUUnityOperationError(
                    "closeProducer requires initializeSendTransport to succeed first."
                )
            }

            guard let activeState = sendState.activeProducers.removeValue(forKey: trackKind) else {
                throw MediaSFUUnityOperationError(
                    "closeProducer requires an active \(trackKind.mediaTag) producer."
                )
            }

            return activeState
        }

        activeState.producer.close()
        activeState.trackResource.dispose()
    }

    private func initializeReceiveTransport(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.initializeReceiveTransport)
        let remoteProducerId = try parseRemoteProducerId(
            payload,
            operationName: OperationNames.initializeReceiveTransport
        )
        let transport = try parseTransportPayload(payload, operationName: OperationNames.initializeReceiveTransport)

        let previousState = withStateLock { () -> PendingReceiveTransportState? in
            receiveTransportStates.removeValue(forKey: remoteProducerId)
        }
        previousState?.close()

        let nextState = PendingReceiveTransportState(
            remoteProducerId: remoteProducerId,
            transportId: transport.id,
            transport: try device.createRecvTransport(params: try buildTransportParams(
                transport,
                operationName: OperationNames.initializeReceiveTransport
            ))
        )

        nextState.transport.setOnConnect { [weak nextState] dtlsParametersJson, callback, errback in
            guard let nextState else { return }
            let connectData = PendingConnectData(
                dtlsParametersJson: self.canonicalizeJsonIfPossible(dtlsParametersJson),
                callback: callback,
                errback: errback
            )

            self.withStateLock {
                nextState.activeConnectData = connectData
            }
            nextState.pendingConnectData.resolve(connectData)
        }

        nextState.transport.setOnConnectionStateChange { [weak nextState] state in
            guard let nextState else { return }
            guard self.isTerminalTransportState(state) else {
                return
            }

            nextState.pendingConnectData.reject(
                MediaSFUUnityOperationError(
                    "Receive transport \(nextState.transportId) for remote producer \(nextState.remoteProducerId) entered \(state) before connect completion."
                )
            )
        }

        withStateLock {
            receiveTransportStates[remoteProducerId] = nextState
        }
    }

    private func createReceiveTransportConnectParameters(payloadJson: String) throws -> Any {
        let payload = try decodePayloadObject(
            payloadJson,
            operationName: OperationNames.createReceiveTransportConnectParameters
        )
        let remoteProducerId = try parseRemoteProducerId(
            payload,
            operationName: OperationNames.createReceiveTransportConnectParameters
        )
        let state = try requireReceiveTransportState(
            remoteProducerId: remoteProducerId,
            operationName: OperationNames.createReceiveTransportConnectParameters
        )
        let connectData = try resolveReceiveConnectData(
            state,
            remoteProducerId: remoteProducerId,
            operationName: OperationNames.createReceiveTransportConnectParameters
        )

        return [
            "dtlsParametersJson": connectData.dtlsParametersJson
        ]
    }

    private func completeReceiveTransportConnect(payloadJson: String) throws {
        let payload = try decodePayloadObject(
            payloadJson,
            operationName: OperationNames.completeReceiveTransportConnect
        )
        let remoteProducerId = try parseRemoteProducerId(
            payload,
            operationName: OperationNames.completeReceiveTransportConnect
        )
        let state = try requireReceiveTransportState(
            remoteProducerId: remoteProducerId,
            operationName: OperationNames.completeReceiveTransportConnect
        )
        let connectData = try resolveReceiveConnectData(
            state,
            remoteProducerId: remoteProducerId,
            operationName: OperationNames.completeReceiveTransportConnect
        )

        withStateLock {
            state.activeConnectData = nil
        }

        if boolValue(payload, key: "success") {
            connectData.callback()
            return
        }

        let detail = optionalString(payload, key: "errorDetail").takeUnlessBlank()
            ?? "Receive transport connect failed."
        connectData.errback(MediaSFUUnityOperationError(detail))
    }

    private func bindConsumer(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.bindConsumer)
        let remoteProducerId = try parseRemoteProducerId(payload, operationName: OperationNames.bindConsumer)
        let consumeResponse = try requireObject(
            payload,
            key: "consumeResponse",
            message: "bindConsumer requires a consumeResponse payload."
        )
        let state = try requireReceiveTransportState(
            remoteProducerId: remoteProducerId,
            operationName: OperationNames.bindConsumer
        )

        try withStateLock {
            if state.activeConsumer != nil {
                throw MediaSFUUnityOperationError(
                    "bindConsumer already has an active consumer for remote producer \(remoteProducerId)."
                )
            }
        }

        let consumerId = try requiredNonEmptyString(
            consumeResponse,
            key: "consumerId",
            message: "bindConsumer requires a non-empty consumeResponse.consumerId."
        )
        let producerId = optionalString(consumeResponse, key: "producerId").takeUnlessBlank() ?? remoteProducerId
        let kind = try requiredNonEmptyString(
            consumeResponse,
            key: "kind",
            message: "bindConsumer requires a non-empty consumeResponse.kind."
        ).lowercased()
        let rtpParametersJson = try requiredNonEmptyString(
            consumeResponse,
            key: "rtpParametersJson",
            message: "bindConsumer requires a non-empty consumeResponse.rtpParametersJson."
        )
        let consumer = try state.transport.consume(
            id: consumerId,
            producerId: producerId,
            kind: kind,
            rtpParametersJson: canonicalizeJsonIfPossible(rtpParametersJson)
        )

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
        let videoRenderer: MediaSFUUnityRemoteVideoFrameRenderer?
        if let videoTrack = consumer.track as? RTCVideoTrack {
            let renderer = MediaSFUUnityRemoteVideoFrameRenderer()
            videoTrack.add(renderer)
            videoRenderer = renderer
        } else {
            videoRenderer = nil
        }
#else
        let videoRenderer: Any? = nil
#endif

        withStateLock {
            state.activeConsumer = consumer
#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
            state.videoRenderer = videoRenderer
#endif
        }
    }

    private func getRemoteVideoFrameMetadata(payloadJson: String) throws -> Any {
        let payload = try decodePayloadObject(
            payloadJson,
            operationName: OperationNames.getRemoteVideoFrameMetadata
        )
        let remoteProducerId = try requiredNonEmptyString(
            payload,
            key: "remoteProducerId",
            message: "getRemoteVideoFrameMetadata requires a non-empty remoteProducerId."
        )

        let metadata = withStateLock {
            guard let resolution = resolveReceiveTransportState(forFrameLookupId: remoteProducerId) else {
                return [
                    "available": false,
                    "resolvedBy": "none",
                    "remoteProducerId": "",
                    "consumerId": "",
                    "trackId": "",
                    "consumerKind": "",
                    "rendererAttached": false,
                    "consumerPaused": false,
                    "consumerStatsJson": "",
                ]
            }

            #if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
            var metadata: [String: Any] = resolution.state.videoRenderer?.metadataDictionary() ?? ["available": false]
            #else
            var metadata: [String: Any] = ["available": false]
            #endif
            metadata["resolvedBy"] = resolution.resolvedBy
            metadata["remoteProducerId"] = resolution.state.remoteProducerId
            metadata["consumerId"] = resolution.state.activeConsumer?.id ?? ""
            #if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
            metadata["trackId"] = resolution.state.activeConsumer?.track?.trackId ?? ""
            #else
            metadata["trackId"] = ""
            #endif
            metadata["consumerKind"] = resolution.state.activeConsumer?.kind ?? ""
            #if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
            metadata["rendererAttached"] = resolution.state.videoRenderer != nil
            #else
            metadata["rendererAttached"] = false
            #endif
            metadata["consumerPaused"] = resolution.state.activeConsumer?.paused ?? false
            metadata["consumerStatsJson"] = resolution.state.activeConsumer?.getStatsJson() ?? ""
            return metadata
        }

        return metadata
    }

    private func resolveReceiveTransportState(forFrameLookupId lookupId: String) -> (
        state: PendingReceiveTransportState,
        resolvedBy: String
    )? {
        if let directState = receiveTransportStates[lookupId] {
            return (directState, "remoteProducerId")
        }

        if let consumerState = receiveTransportStates.values.first(where: { state in
            state.activeConsumer?.id == lookupId
        }) {
            return (consumerState, "consumerId")
        }

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
        if let trackState = receiveTransportStates.values.first(where: { state in
            state.activeConsumer?.track?.trackId == lookupId
        }) {
            return (trackState, "trackId")
        }
#endif

        return nil
    }

    private func closeConsumer(payloadJson: String) throws {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.closeConsumer)
        let remoteProducerId = try requiredNonEmptyString(
            payload,
            key: "remoteProducerId",
            message: "closeConsumer requires a non-empty remoteProducerId."
        )
        let state = withStateLock { receiveTransportStates.removeValue(forKey: remoteProducerId) }
        state?.close()
    }

    private func requireSendTransportState(operationName: String) throws -> PendingSendTransportState {
        guard let state = withStateLock({ sendTransportState }) else {
            throw MediaSFUUnityOperationError(
                "\(operationName) requires initializeSendTransport to succeed first."
            )
        }

        return state
    }

    private func requireReceiveTransportState(
        remoteProducerId: String,
        operationName: String
    ) throws -> PendingReceiveTransportState {
        guard let state = withStateLock({ receiveTransportStates[remoteProducerId] }) else {
            throw MediaSFUUnityOperationError(
                "\(operationName) requires initializeReceiveTransport to succeed first for remote producer \(remoteProducerId)."
            )
        }

        return state
    }

    private func requireActiveProducerState(
        trackKind: MediaSFUUnityTrackKind,
        operationName: String
    ) throws -> ActiveProducerState {
        try withStateLock {
            guard let sendState = sendTransportState else {
                throw MediaSFUUnityOperationError(
                    "\(operationName) requires initializeSendTransport to succeed first."
                )
            }

            guard let activeState = sendState.activeProducers[trackKind] else {
                throw MediaSFUUnityOperationError(
                    "\(operationName) requires an active \(trackKind.mediaTag) producer."
                )
            }

            return activeState
        }
    }

    private func resolveSendConnectData(
        _ state: PendingSendTransportState,
        operationName: String
    ) throws -> PendingConnectData {
        if let activeData = withStateLock({ state.activeConnectData }) {
            return activeData
        }

        let connectData = try state.pendingConnectData.await(
            timeout: connectEventTimeout,
            timeoutMessage: "\(operationName) timed out waiting for iOS mediasoup send transport connect parameters."
        )
        withStateLock {
            state.activeConnectData = connectData
        }
        return connectData
    }

    private func resolveReceiveConnectData(
        _ state: PendingReceiveTransportState,
        remoteProducerId: String,
        operationName: String
    ) throws -> PendingConnectData {
        if let activeData = withStateLock({ state.activeConnectData }) {
            return activeData
        }

        let connectData = try state.pendingConnectData.await(
            timeout: connectEventTimeout,
            timeoutMessage: "\(operationName) timed out waiting for iOS mediasoup receive transport connect parameters for remote producer \(remoteProducerId)."
        )
        withStateLock {
            state.activeConnectData = connectData
        }
        return connectData
    }

    private func parseCreateProduceRequestPayload(_ payloadJson: String) throws -> CreateProduceRequestPayload {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.createProduceRequest)
        let trackKindValue = try requiredInt(
            payload,
            key: "trackKind",
            message: "createProduceRequest requires a supported trackKind value."
        )
        guard let trackKind = MediaSFUUnityTrackKind(rawValue: trackKindValue) else {
            throw MediaSFUUnityOperationError(
                "Unsupported Unity trackKind value: \(trackKindValue)"
            )
        }

        return CreateProduceRequestPayload(
            trackKind: trackKind,
            enabled: boolValue(payload, key: "enabled"),
            localUserName: optionalString(payload, key: "localUserName"),
            localIsLevel: optionalString(payload, key: "localIsLevel"),
            participantName: optionalString(payload, key: "participantName"),
            participantIsLevel: optionalString(payload, key: "participantIslevel")
        )
    }

    private func parseBindProducerPayload(_ payloadJson: String) throws -> BindProducerPayload {
        let payload = try decodePayloadObject(payloadJson, operationName: OperationNames.bindProducer)
        let trackKindValue = try requiredInt(
            payload,
            key: "trackKind",
            message: "bindProducer requires a supported trackKind value."
        )
        guard let trackKind = MediaSFUUnityTrackKind(rawValue: trackKindValue) else {
            throw MediaSFUUnityOperationError(
                "Unsupported Unity trackKind value: \(trackKindValue)"
            )
        }

        return BindProducerPayload(
            trackKind: trackKind,
            producerId: try requiredNonEmptyString(
                payload,
                key: "producerId",
                message: "bindProducer requires a non-empty producerId."
            )
        )
    }

    private func parseTrackOperationPayload(
        _ payloadJson: String,
        operationName: String
    ) throws -> MediaSFUUnityTrackKind {
        let payload = try decodePayloadObject(payloadJson, operationName: operationName)
        let trackKindValue = try requiredInt(
            payload,
            key: "trackKind",
            message: "\(operationName) requires a supported trackKind value."
        )
        guard let trackKind = MediaSFUUnityTrackKind(rawValue: trackKindValue) else {
            throw MediaSFUUnityOperationError(
                "Unsupported Unity trackKind value: \(trackKindValue)"
            )
        }

        return trackKind
    }

    private func parseTransportPayload(
        _ payload: [String: Any],
        operationName: String
    ) throws -> UnityWebRtcTransportPayload {
        let transportPayload = try requireObject(
            payload,
            key: "transport",
            message: "\(operationName) requires a transport payload."
        )

        return UnityWebRtcTransportPayload(
            id: try requiredNonEmptyString(
                transportPayload,
                key: "id",
                message: "\(operationName) requires a transport payload with a non-empty id."
            ),
            iceParametersJson: try requiredNonEmptyString(
                transportPayload,
                key: "iceParametersJson",
                message: "\(operationName) requires a non-empty transport.iceParametersJson value."
            ),
            iceCandidatesJson: try requiredNonEmptyString(
                transportPayload,
                key: "iceCandidatesJson",
                message: "\(operationName) requires a non-empty transport.iceCandidatesJson value."
            ),
            dtlsParametersJson: try requiredNonEmptyString(
                transportPayload,
                key: "dtlsParametersJson",
                message: "\(operationName) requires a non-empty transport.dtlsParametersJson value."
            ),
            sctpParametersJson: optionalString(transportPayload, key: "sctpParametersJson"),
            rawPayload: optionalString(transportPayload, key: "rawPayload")
        )
    }

    private func parseRemoteProducerId(
        _ payload: [String: Any],
        operationName: String
    ) throws -> String {
        let remoteProducer = try requireObject(
            payload,
            key: "remoteProducer",
            message: "\(operationName) requires a remoteProducer with a non-empty producerId."
        )

        return try requiredNonEmptyString(
            remoteProducer,
            key: "producerId",
            message: "\(operationName) requires a remoteProducer with a non-empty producerId."
        )
    }

    private func buildTransportParams(
        _ transport: UnityWebRtcTransportPayload,
        operationName: String
    ) throws -> [String: Any?] {
        var params: [String: Any?] = [
            "id": transport.id,
            "iceParameters": try decodeJsonValue(
                transport.iceParametersJson,
                fieldName: "transport.iceParametersJson",
                operationName: operationName
            ),
            "iceCandidates": try decodeJsonValue(
                transport.iceCandidatesJson,
                fieldName: "transport.iceCandidatesJson",
                operationName: operationName
            ),
            "dtlsParameters": try decodeJsonValue(
                transport.dtlsParametersJson,
                fieldName: "transport.dtlsParametersJson",
                operationName: operationName
            )
        ]

        if let sctpParametersJson = transport.sctpParametersJson.takeUnlessBlank() {
            params["sctpParameters"] = try decodeJsonValue(
                sctpParametersJson,
                fieldName: "transport.sctpParametersJson",
                operationName: operationName
            )
        }

        if let appData = try extractAppData(rawPayload: transport.rawPayload) {
            params["appData"] = appData
        }

        return params
    }

    private func extractAppData(rawPayload: String) throws -> Any? {
        guard let rawPayload = rawPayload.takeUnlessBlank() else {
            return nil
        }

        guard let root = try decodeJsonValueOrNil(rawPayload) as? [String: Any] else {
            return nil
        }

        return root["appData"]
    }

    private func buildProduceAppDataJson(trackKind: MediaSFUUnityTrackKind) throws -> String {
        try MediaSFUBridgeJson.encode([
            "mediaTag": trackKind.mediaTag,
            "trackKind": trackKind.rawValue
        ])
    }

    private func resolveTrackKind(kind: String, appDataJson: String?) throws -> MediaSFUUnityTrackKind {
          if let appDataJson = appDataJson?.takeUnlessBlank(),
           let appData = try decodeJsonValueOrNil(appDataJson) as? [String: Any] {
            if let trackKindValue = intValue(appData["trackKind"]),
               let trackKind = MediaSFUUnityTrackKind(rawValue: trackKindValue) {
                return trackKind
            }

            if let mediaTag = stringValue(appData["mediaTag"])?.takeUnlessBlank(),
               let trackKind = trackKind(forMediaTag: mediaTag) {
                return trackKind
            }
        }

        if let trackKind = trackKind(forMediaTag: kind) {
            return trackKind
        }

        throw MediaSFUUnityOperationError(
            "Unsupported Unity track kind in produce callback: \(kind)."
        )
    }

    private func trackKind(forMediaTag value: String) -> MediaSFUUnityTrackKind? {
        switch value.lowercased() {
        case "audio":
            return .audio
        case "video":
            return .video
        case "screen":
            return .screen
        case "whiteboard":
            return .whiteboard
        default:
            return nil
        }
    }

    private func decodePayloadObject(
        _ payloadJson: String,
        operationName: String
    ) throws -> [String: Any] {
        let normalizedPayload = payloadJson.takeUnlessBlank() ?? "{}"
        do {
            return try MediaSFUBridgeJson.decodeObject(normalizedPayload)
        } catch {
            throw MediaSFUUnityOperationError(
                "\(operationName) received invalid JSON payload: \(error.localizedDescription)"
            )
        }
    }

    private func decodeJsonValue(
        _ payload: String,
        fieldName: String,
        operationName: String
    ) throws -> Any {
        guard let value = try decodeJsonValueOrNil(payload) else {
            throw MediaSFUUnityOperationError(
                "\(operationName) requires a non-empty \(fieldName) value."
            )
        }

        return value
    }

    private func decodeJsonValueOrNil(_ payload: String) throws -> Any? {
        guard payload.takeUnlessBlank() != nil else {
            return nil
        }

        do {
            return try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [])
        } catch {
            throw MediaSFUUnityOperationError(error.localizedDescription)
        }
    }

    private func canonicalizeJson(_ payload: String) throws -> String {
        let value = try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [])
        guard JSONSerialization.isValidJSONObject(value) else {
            throw MediaSFUUnityOperationError("JSON payload must decode to an object or array.")
        }

        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let canonical = String(data: data, encoding: .utf8) else {
            throw MediaSFUUnityOperationError("JSON payload could not be converted back to UTF-8.")
        }

        return canonical
    }

    private func canonicalizeJsonIfPossible(_ payload: String) -> String {
        (try? canonicalizeJson(payload)) ?? payload
    }

    private func invokeVoidOperation(_ block: () throws -> Void) -> String {
        do {
            try block()
            return successResponse(result: NSNull())
        } catch {
            return failedOperationResponse(error)
        }
    }

    private func invokeJsonOperation(_ block: () throws -> Any) -> String {
        do {
            return successResponse(result: try block())
        } catch {
            return failedOperationResponse(error)
        }
    }

    private func successResponse(result: Any) -> String {
        encodeResponse(success: true, error: "", detail: "", result: result)
    }

    private func failedOperationResponse(_ error: Error) -> String {
        encodeResponse(
            success: false,
            error: ErrorCodes.operationFailed,
            detail: error.localizedDescription,
            result: NSNull()
        )
    }

    private func unknownOperationResponse(operationName: String) -> String {
        encodeResponse(
            success: false,
            error: ErrorCodes.unknownOperation,
            detail: "\(describe()) does not recognize operation \(operationName).",
            result: NSNull()
        )
    }

    private func encodeResponse(success: Bool, error: String, detail: String, result: Any) -> String {
        if let encoded = try? MediaSFUBridgeJson.encode([
            "success": success,
            "error": error,
            "detail": detail,
            "result": result
        ]) {
            return encoded
        }

        return success
            ? "{\"success\":true,\"error\":\"\",\"detail\":\"\",\"result\":null}"
            : "{\"success\":false,\"error\":\"native_bridge_operation_failed\",\"detail\":\"MediaSFU iOS Unity operation host failed while encoding a response.\",\"result\":null}"
    }

    private func requiredNonEmptyString(
        _ object: [String: Any],
        key: String,
        message: String
    ) throws -> String {
        guard let value = stringValue(object[key])?.takeUnlessBlank() else {
            throw MediaSFUUnityOperationError(message)
        }

        return value
    }

    private func requiredInt(
        _ object: [String: Any],
        key: String,
        message: String
    ) throws -> Int {
        guard let value = intValue(object[key]) else {
            throw MediaSFUUnityOperationError(message)
        }

        return value
    }

    private func requireObject(
        _ object: [String: Any],
        key: String,
        message: String
    ) throws -> [String: Any] {
        guard let value = object[key] as? [String: Any] else {
            throw MediaSFUUnityOperationError(message)
        }

        return value
    }

    private func optionalString(_ object: [String: Any], key: String) -> String {
        stringValue(object[key]) ?? ""
    }

    private func boolValue(_ object: [String: Any], key: String) -> Bool {
        switch object[key] {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        default:
            return false
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSString:
            return value as String
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }

    private func isTerminalTransportState(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "closed" || normalized == "failed"
    }

    private func withStateLock<T>(_ block: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try block()
    }

    private static func unsupportedTrackFactory() -> LocalTrackFactory {
        { trackKind in
            throw MediaSFUUnityOperationError(
                "createProduceRequest requires a local track factory for \(trackKind.mediaTag)."
            )
        }
    }

    private struct CreateProduceRequestPayload {
        let trackKind: MediaSFUUnityTrackKind
        let enabled: Bool
        let localUserName: String
        let localIsLevel: String
        let participantName: String
        let participantIsLevel: String
    }

    private struct BindProducerPayload {
        let trackKind: MediaSFUUnityTrackKind
        let producerId: String
    }

    private struct UnityWebRtcTransportPayload {
        let id: String
        let iceParametersJson: String
        let iceCandidatesJson: String
        let dtlsParametersJson: String
        let sctpParametersJson: String
        let rawPayload: String
    }

    private struct PendingConnectData {
        let dtlsParametersJson: String
        let callback: () -> Void
        let errback: (Error) -> Void
    }

    private struct PendingProduceData {
        let kind: String
        let rtpParametersJson: String
        let appDataJson: String?
        let callback: (String?) -> Void
        let errback: (Error) -> Void
    }

    private final class PendingSendTransportState {
        let transportId: String
        let transport: MediaSFUSendTransportAdapter
        let pendingConnectData = PendingSignalBox<PendingConnectData>()
        var activeConnectData: PendingConnectData?
        var activeProducers: [MediaSFUUnityTrackKind: ActiveProducerState] = [:]
        var pendingProduceStates: [MediaSFUUnityTrackKind: PendingProduceState] = [:]

        init(transportId: String, transport: MediaSFUSendTransportAdapter) {
            self.transportId = transportId
            self.transport = transport
        }

        func close(reason: String) {
            for pendingState in pendingProduceStates.values {
                pendingState.trackResource.dispose()
                pendingState.produceData.reject(MediaSFUUnityOperationError(reason))
                pendingState.producerReady.reject(MediaSFUUnityOperationError(reason))
            }

            for activeState in activeProducers.values {
                activeState.producer.close()
                activeState.trackResource.dispose()
            }

            pendingProduceStates.removeAll()
            activeProducers.removeAll()
            transport.close()
        }
    }

    private final class PendingProduceState {
        let trackKind: MediaSFUUnityTrackKind
        let participantName: String
        let participantIsLevel: String
        let trackResource: MediaSFUUnityLocalTrackResource
        let produceData = PendingSignalBox<PendingProduceData>()
        let producerReady = PendingSignalBox<MediaSFUProducerAdapter>()
        var activeProduceData: PendingProduceData?

        init(
            trackKind: MediaSFUUnityTrackKind,
            participantName: String,
            participantIsLevel: String,
            trackResource: MediaSFUUnityLocalTrackResource
        ) {
            self.trackKind = trackKind
            self.participantName = participantName
            self.participantIsLevel = participantIsLevel
            self.trackResource = trackResource
        }
    }

    private struct ActiveProducerState {
        let producer: MediaSFUProducerAdapter
        let trackResource: MediaSFUUnityLocalTrackResource
    }

    private final class PendingReceiveTransportState {
        let remoteProducerId: String
        let transportId: String
        let transport: MediaSFURecvTransportAdapter
        let pendingConnectData = PendingSignalBox<PendingConnectData>()
        var activeConnectData: PendingConnectData?
        var activeConsumer: MediaSFUConsumerAdapter?
#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
        var videoRenderer: MediaSFUUnityRemoteVideoFrameRenderer?
#endif

        init(remoteProducerId: String, transportId: String, transport: MediaSFURecvTransportAdapter) {
            self.remoteProducerId = remoteProducerId
            self.transportId = transportId
            self.transport = transport
        }

        func close() {
#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
            if let videoRenderer, let videoTrack = activeConsumer?.track as? RTCVideoTrack {
                videoTrack.remove(videoRenderer)
            }
            videoRenderer = nil
#endif
            activeConsumer?.close()
            transport.close()
        }
    }

    private final class PendingSignalBox<Value> {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var result: Result<Value, Error>?

        func resolve(_ value: Value) {
            complete(.success(value))
        }

        func reject(_ error: Error) {
            complete(.failure(error))
        }

        func await(timeout: TimeInterval, timeoutMessage: String) throws -> Value {
            if let currentResult = currentResult() {
                return try currentResult.get()
            }

            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                throw MediaSFUUnityOperationError(timeoutMessage)
            }

            guard let currentResult = currentResult() else {
                throw MediaSFUUnityOperationError(timeoutMessage)
            }

            return try currentResult.get()
        }

        private func currentResult() -> Result<Value, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }

        private func complete(_ nextResult: Result<Value, Error>) {
            lock.lock()
            let shouldSignal = result == nil
            if shouldSignal {
                result = nextResult
            }
            lock.unlock()

            if shouldSignal {
                semaphore.signal()
            }
        }
    }

    private struct MediaSFUUnityOperationError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }

    private enum OperationNames {
        static let describeBackend = "describeBackend"
        static let loadDeviceRtpCapabilities = "loadDeviceRtpCapabilities"
        static let initializeSendTransport = "initializeSendTransport"
        static let createSendTransportConnectParameters = "createSendTransportConnectParameters"
        static let completeSendTransportConnect = "completeSendTransportConnect"
        static let createProduceRequest = "createProduceRequest"
        static let bindProducer = "bindProducer"
        static let pauseProducer = "pauseProducer"
        static let resumeProducer = "resumeProducer"
        static let closeProducer = "closeProducer"
        static let initializeReceiveTransport = "initializeReceiveTransport"
        static let createReceiveTransportConnectParameters = "createReceiveTransportConnectParameters"
        static let completeReceiveTransportConnect = "completeReceiveTransportConnect"
        static let bindConsumer = "bindConsumer"
        static let getRemoteVideoFrameMetadata = "getRemoteVideoFrameMetadata"
        static let closeConsumer = "closeConsumer"
    }

    private enum ErrorCodes {
        static let operationFailed = "native_bridge_operation_failed"
        static let unknownOperation = "native_bridge_unknown_operation"
    }
}

private extension String {
    func takeUnlessBlank() -> String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
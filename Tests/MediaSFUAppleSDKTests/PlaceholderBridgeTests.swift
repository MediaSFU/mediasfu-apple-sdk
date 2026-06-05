import XCTest
@testable import MediaSFUAppleSDK

final class PlaceholderBridgeTests: XCTestCase {
    func testPlaceholderBridgeCreatesHandles() {
        let bridge = PlaceholderMediasoupBridge()

        let send = bridge.createSendTransport(params: [:])
        let recv = bridge.createRecvTransport(params: [:])

        XCTAssertEqual(send.connectionState(), "new")
        XCTAssertEqual(recv.connectionState(), "new")
        XCTAssertFalse(send.id.isEmpty)
        XCTAssertFalse(recv.id.isEmpty)
    }

    func testPlaceholderTransportCloseUpdatesState() {
        let bridge = PlaceholderMediasoupBridge()
        let send = bridge.createSendTransport(params: [:])

        send.close()

        XCTAssertEqual(send.connectionState(), "closed")
    }

    func testJsonHelpersRoundTripObject() throws {
        let json = try MediaSFUBridgeJson.encode([
            "role": "auto",
            "fingerprints": [
                ["algorithm": "sha-256", "value": "abc"]
            ],
            "appData": ["source": "camera", "enabled": true] as [String : Any]
        ])

        let decoded = try MediaSFUBridgeJson.decodeObject(json)

        XCTAssertEqual(decoded["role"] as? String, "auto")
        XCTAssertEqual((decoded["fingerprints"] as? [[String: Any]])?.count, 1)
    }

    func testPlaceholderConnectTriggerPassesJsonAndCallbacks() throws {
        let send = PlaceholderSendTransportHandle(id: "send", params: [:])
        var receivedRole: String?
        var callbackCalled = false

        send.setOnConnect { dtlsJson, callback, _ in
            receivedRole = try? MediaSFUBridgeJson.decodeObject(dtlsJson)["role"] as? String
            callback()
        }

        try send.triggerOnConnect(
            dtlsParameters: ["role": "client"],
            onCallback: { callbackCalled = true }
        )

        XCTAssertEqual(receivedRole, "client")
        XCTAssertTrue(callbackCalled)
    }

    func testPlaceholderProduceTriggerPassesRtpAndAppData() throws {
        let send = PlaceholderSendTransportHandle(id: "send", params: [:])
        var receivedKind: String?
        var receivedMid: String?
        var receivedSource: String?
        var callbackProducerId: String?

        send.setOnProduce { kind, rtpJson, appDataJson, callback, _ in
            receivedKind = kind
            receivedMid = try? MediaSFUBridgeJson.decodeObject(rtpJson)["mid"] as? String
            if let appDataJson {
                receivedSource = try? MediaSFUBridgeJson.decodeObject(appDataJson)["source"] as? String
            }
            callback("producer-123")
        }

        try send.triggerOnProduce(
            kind: "video",
            rtpParameters: ["mid": "1"],
            appData: ["source": "camera"],
            onCallback: { callbackProducerId = $0 }
        )

        XCTAssertEqual(receivedKind, "video")
        XCTAssertEqual(receivedMid, "1")
        XCTAssertEqual(receivedSource, "camera")
        XCTAssertEqual(callbackProducerId, "producer-123")
    }

    func testPlaceholderStateListenerReceivesTransitions() {
        let send = PlaceholderSendTransportHandle(id: "send", params: [:])
        var states: [String] = []

        send.setOnConnectionStateChange { state in
            states.append(state)
        }

        send.updateState("connecting")
        send.updateState("connected")
        send.close()

        XCTAssertEqual(states, ["connecting", "connected", "closed"])
    }

    func testPlaceholderRecvTransportCapturesConsumeArguments() throws {
        let recv = PlaceholderRecvTransportHandle(id: "recv", params: [:])
        let rtpJson = try MediaSFUBridgeJson.encode([
            "mid": "2",
            "codecs": [["mimeType": "audio/opus"]]
        ])

        let consumer = recv.consume(
            id: "consumer-1",
            producerId: "producer-9",
            kind: "audio",
            rtpParametersJson: rtpJson
        )

        XCTAssertEqual(consumer.id, "consumer-1")
        XCTAssertEqual(recv.lastProducerId, "producer-9")
        XCTAssertEqual(recv.lastConsumerKind, "audio")
        XCTAssertEqual(try recv.decodedLastRtpParameters()["mid"] as? String, "2")
    }

    func testBridgeErrorDescriptionsAreStable() {
        XCTAssertEqual(
            MediaSFUBridgeError.connectFailed("missing dtls").errorDescription,
            "Connect failed: missing dtls"
        )
        XCTAssertEqual(
            MediaSFUBridgeError.produceFailed("missing producer id").errorDescription,
            "Produce failed: missing producer id"
        )
    }

    func testDeviceBackedBridgeCreatesAdapterBackedHandles() {
        let device = FakeDeviceAdapter()
        let bridge = DeviceBackedMediasoupBridge(device: device)

        let send = bridge.createSendTransport(params: ["direction": "send"])
        let recv = bridge.createRecvTransport(params: ["direction": "recv"])

        XCTAssertEqual(device.lastSendParams?["direction"] as? String, "send")
        XCTAssertEqual(device.lastRecvParams?["direction"] as? String, "recv")
        XCTAssertEqual(send.id, "send-adapter")
        XCTAssertEqual(recv.id, "recv-adapter")
    }

    func testDeviceBackedBridgeForwardsConnectProduceAndState() throws {
        let device = FakeDeviceAdapter()
        let bridge = DeviceBackedMediasoupBridge(device: device)
        let send = bridge.createSendTransport(params: [:])
        var states: [String] = []
        var receivedRole: String?
        var producedId: String?

        send.setOnConnectionStateChange { states.append($0) }
        send.setOnConnect { dtlsJson, callback, _ in
            receivedRole = try? MediaSFUBridgeJson.decodeObject(dtlsJson)["role"] as? String
            callback()
        }
        send.setOnProduce { _, _, _, callback, _ in
            callback("producer-from-adapter")
        }

        device.sendTransport.emitState("connecting")
        device.sendTransport.emitConnect(dtlsJson: try MediaSFUBridgeJson.encode(["role": "server"]))
        let producer = send.produce(
            track: FakeTrack(),
            encodingsJson: nil,
            appDataJson: try MediaSFUBridgeJson.encode(["source": "mic"])
        )
        producedId = producer.id

        XCTAssertEqual(states, ["connecting"])
        XCTAssertEqual(receivedRole, "server")
        XCTAssertEqual(producedId, "producer-from-adapter")
        XCTAssertEqual(device.sendTransport.lastProducedAppDataJson.flatMap { try? MediaSFUBridgeJson.decodeObject($0)["source"] as? String }, "mic")
    }

    func testDeviceBackedBridgeForwardsConsume() throws {
        let device = FakeDeviceAdapter()
        let bridge = DeviceBackedMediasoupBridge(device: device)
        let recv = bridge.createRecvTransport(params: [:])
        let rtpJson = try MediaSFUBridgeJson.encode(["mid": "3"])

        let consumer = recv.consume(
            id: "consumer-a",
            producerId: "producer-b",
            kind: "video",
            rtpParametersJson: rtpJson
        )

        XCTAssertEqual(consumer.id, "consumer-a")
        XCTAssertEqual(device.recvTransport.lastConsumeId, "consumer-a")
        XCTAssertEqual(device.recvTransport.lastConsumeProducerId, "producer-b")
        XCTAssertEqual(device.recvTransport.lastConsumeKind, "video")
        XCTAssertEqual(device.recvTransport.lastConsumeRtpJson, rtpJson)
    }

    func testClientBackedDeviceAdapterParsesTransportCreationOptions() throws {
        let clientDevice = FakeNativeClientDevice()
        let adapter = ClientBackedDeviceAdapter(clientDevice: clientDevice)

        _ = try adapter.createSendTransport(params: [
            "id": "send-1",
            "iceParameters": ["usernameFragment": "abc"],
            "iceCandidates": [["protocol": "udp"]],
            "dtlsParameters": ["role": "auto"],
            "sctpParameters": ["port": 5000],
            "appData": ["source": "camera"]
        ])

        XCTAssertEqual(clientDevice.lastSendOptions?.id, "send-1")
        XCTAssertEqual(try MediaSFUBridgeJson.decodeObject(clientDevice.lastSendOptions?.iceParametersJson ?? "{}")["usernameFragment"] as? String, "abc")
        XCTAssertEqual(try MediaSFUBridgeJson.decodeArray(clientDevice.lastSendOptions?.iceCandidatesJson ?? "[]").count, 1)
        XCTAssertEqual(try MediaSFUBridgeJson.decodeObject(clientDevice.lastSendOptions?.dtlsParametersJson ?? "{}")["role"] as? String, "auto")
        XCTAssertEqual(try MediaSFUBridgeJson.decodeObject(clientDevice.lastSendOptions?.appDataJson ?? "{}")["source"] as? String, "camera")
    }

    func testClientBackedDeviceAdapterForwardsProduceAndConsume() throws {
        let clientDevice = FakeNativeClientDevice()
        let sendAdapter = try clientDeviceAdapter(clientDevice).createSendTransport(params: validTransportParams(id: "send-2"))
        let recvAdapter = try clientDeviceAdapter(clientDevice).createRecvTransport(params: validTransportParams(id: "recv-2"))

        let producer = try sendAdapter.produce(
            track: FakeTrack(),
            encodingsJson: "{\"active\":true}",
            appDataJson: "{\"source\":\"screen\"}"
        )
        let consumer = try recvAdapter.consume(
            id: "consumer-z",
            producerId: "producer-y",
            kind: "audio",
            rtpParametersJson: "{\"mid\":\"9\"}"
        )

        XCTAssertEqual(producer.id, "native-producer")
        XCTAssertEqual(clientDevice.sendTransport.lastProduceOptions?.appDataJson, "{\"source\":\"screen\"}")
        XCTAssertEqual(consumer.id, "consumer-z")
        XCTAssertEqual(clientDevice.recvTransport.lastConsumeOptions?.producerId, "producer-y")
    }

    func testClientBackedDeviceAdapterRejectsMissingTransportId() {
        let clientDevice = FakeNativeClientDevice()
        let adapter = ClientBackedDeviceAdapter(clientDevice: clientDevice)

        XCTAssertThrowsError(try adapter.createSendTransport(params: [:]))
    }

    func testLibmediasoupClientAdapterPassesTransportOptions() throws {
        let device = FakeLibmediasoupDevice()
        let adapter = LibmediasoupClientDeviceAdapter(device: device)

        _ = try adapter.createSendTransport(params: [
            "id": "lib-send",
            "iceParameters": ["usernameFragment": "ufrag"],
            "iceCandidates": [["foundation": "1"]],
            "dtlsParameters": ["role": "auto"],
            "sctpParameters": ["port": 5000],
            "appData": ["mediaTag": "cam-video"]
        ])

        XCTAssertEqual(device.lastSendId, "lib-send")
        XCTAssertEqual(try MediaSFUBridgeJson.decodeObject(device.lastSendIceParametersJson ?? "{}")["usernameFragment"] as? String, "ufrag")
        XCTAssertEqual(try MediaSFUBridgeJson.decodeArray(device.lastSendIceCandidatesJson ?? "[]").count, 1)
        XCTAssertEqual(try MediaSFUBridgeJson.decodeObject(device.lastSendAppDataJson ?? "{}")["mediaTag"] as? String, "cam-video")
    }

    func testLibmediasoupClientAdapterForwardsProduceConsumeAndState() throws {
        let device = FakeLibmediasoupDevice()
        let adapter = LibmediasoupClientDeviceAdapter(device: device)
        let send = try adapter.createSendTransport(params: validTransportParams(id: "send-lib"))
        let recv = try adapter.createRecvTransport(params: validTransportParams(id: "recv-lib"))
        var states: [String] = []

        send.setOnConnectionStateChange { states.append($0) }
        device.sendTransport.emitState("connected")

        let producer = try send.produce(
            track: FakeTrack(),
            encodingsJson: "{\"maxBitrate\":1200000}",
            appDataJson: "{\"source\":\"camera\"}"
        )
        let consumer = try recv.consume(
            id: "consumer-lib",
            producerId: "producer-lib",
            kind: "video",
            rtpParametersJson: "{\"mid\":\"4\"}"
        )

        XCTAssertEqual(states, ["connected"])
        XCTAssertEqual(producer.id, "lib-producer")
        XCTAssertEqual(device.sendTransport.lastEncodingsJson, "{\"maxBitrate\":1200000}")
        XCTAssertEqual(consumer.id, "consumer-lib")
        XCTAssertEqual(device.recvTransport.lastConsumedProducerId, "producer-lib")
    }

    func testLibmediasoupDeviceWrapperBuildsConcreteWrapperObjects() throws {
        let backend = FakeRawLibmediasoupDeviceBackend()
        let device = MediaSFULibmediasoupDeviceWrapper(backend: backend)

        let send = try device.createSendTransport(
            id: "wrapped-send",
            iceParametersJson: "{\"usernameFragment\":\"abc\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: "{\"source\":\"camera\"}"
        )
        let recv = try device.createRecvTransport(
            id: "wrapped-recv",
            iceParametersJson: "{\"usernameFragment\":\"def\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )

        XCTAssertEqual(send.id, "raw-send")
        XCTAssertEqual(recv.id, "raw-recv")
        XCTAssertEqual(backend.lastSendOptions?.id, "wrapped-send")
        XCTAssertEqual(backend.lastRecvOptions?.id, "wrapped-recv")
    }

    func testLibmediasoupTransportWrappersForwardBackendOperations() throws {
        let sendBackend = FakeRawLibmediasoupSendTransportBackend()
        let recvBackend = FakeRawLibmediasoupRecvTransportBackend()
        let send = MediaSFULibmediasoupSendTransportWrapper(backend: sendBackend)
        let recv = MediaSFULibmediasoupRecvTransportWrapper(backend: recvBackend)
        var states: [String] = []

        send.onConnectionStateChange { states.append($0) }
        sendBackend.emitState("connecting")

        let producer = try send.produce(
            track: FakeTrack(),
            encodingsJson: "{\"active\":true}",
            appDataJson: "{\"source\":\"screen\"}"
        )
        let consumer = try recv.consume(
            id: "wrapped-consumer",
            producerId: "wrapped-producer",
            kind: "audio",
            rtpParametersJson: "{\"mid\":\"11\"}"
        )

        XCTAssertEqual(states, ["connecting"])
        XCTAssertEqual(producer.id, "raw-producer")
        XCTAssertEqual(sendBackend.lastProduceOptions?.appDataJson, "{\"source\":\"screen\"}")
        XCTAssertEqual(consumer.id, "wrapped-consumer")
        XCTAssertEqual(recvBackend.lastConsumeOptions?.producerId, "wrapped-producer")
    }

    func testExpectedBackendTemplateForwardsConnectProduceAndState() throws {
        let engine = FakeExpectedLibmediasoupDeviceEngine()
        let backend = MediaSFUExpectedLibmediasoupDeviceBackend(engine: engine)
        let device = MediaSFULibmediasoupDeviceWrapper(backend: backend)
        let send = try device.createSendTransport(
            id: "expected-send",
            iceParametersJson: "{\"usernameFragment\":\"x\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )
        var states: [String] = []
        var receivedRole: String?
        var producedId: String?

        send.onConnectionStateChange { states.append($0) }
        send.onConnect { dtlsJson, callback, _ in
            receivedRole = try? MediaSFUBridgeJson.decodeObject(dtlsJson)["role"] as? String
            callback()
        }
        send.onProduce { _, _, _, callback, _ in
            callback("expected-producer-id")
        }

        engine.sendTransport.emitState("connecting")
        engine.sendTransport.emitConnect(dtlsJson: "{\"role\":\"server\"}")
        let producer = try send.produce(
            track: FakeTrack(),
            encodingsJson: "{\"active\":true}",
            appDataJson: "{\"source\":\"camera\"}"
        )
        producedId = producer.id

        XCTAssertEqual(states, ["connecting"])
        XCTAssertEqual(receivedRole, "server")
        XCTAssertEqual(producedId, "expected-producer")
        XCTAssertEqual(engine.sendTransport.lastProduceOptions?.encodingsJson, "{\"active\":true}")
    }

    func testExpectedBackendTemplateForwardsConsume() throws {
        let engine = FakeExpectedLibmediasoupDeviceEngine()
        let backend = MediaSFUExpectedLibmediasoupDeviceBackend(engine: engine)
        let device = MediaSFULibmediasoupDeviceWrapper(backend: backend)
        let recv = try device.createRecvTransport(
            id: "expected-recv",
            iceParametersJson: "{\"usernameFragment\":\"y\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )

        let consumer = try recv.consume(
            id: "expected-consumer",
            producerId: "expected-producer",
            kind: "video",
            rtpParametersJson: "{\"mid\":\"12\"}"
        )

        XCTAssertEqual(consumer.id, "expected-consumer")
        XCTAssertEqual(engine.recvTransport.lastConsumeOptions?.producerId, "expected-producer")
        XCTAssertEqual(engine.recvTransport.lastConsumeOptions?.kind, "video")
    }

    func testAssumedBindingEngineForwardsConnectProduceAndState() throws {
        let binding = FakeAssumedLibmediasoupDeviceBinding()
        let engine = MediaSFUAssumedLibmediasoupDeviceEngine(binding: binding)
        let backend = MediaSFUExpectedLibmediasoupDeviceBackend(engine: engine)
        let device = MediaSFULibmediasoupDeviceWrapper(backend: backend)
        let send = try device.createSendTransport(
            id: "assumed-send",
            iceParametersJson: "{\"usernameFragment\":\"assumed\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )
        var states: [String] = []
        var receivedRole: String?

        send.onConnectionStateChange { states.append($0) }
        send.onConnect { dtlsJson, callback, _ in
            receivedRole = try? MediaSFUBridgeJson.decodeObject(dtlsJson)["role"] as? String
            callback()
        }
        send.onProduce { _, _, _, callback, _ in
            callback("assumed-callback-producer")
        }

        binding.sendTransport.emitState("connected")
        binding.sendTransport.emitConnect(dtlsJson: "{\"role\":\"server\"}")
        let producer = try send.produce(
            track: FakeTrack(),
            encodingsJson: "{\"scaleResolutionDownBy\":2}",
            appDataJson: "{\"source\":\"screen\"}"
        )

        XCTAssertEqual(states, ["connected"])
        XCTAssertEqual(receivedRole, "server")
        XCTAssertEqual(producer.id, "assumed-producer")
        XCTAssertEqual(binding.sendTransport.lastProduceOptions?.appDataJson, "{\"source\":\"screen\"}")
    }

    func testAssumedBindingEngineForwardsConsumeAndProducerControls() throws {
        let binding = FakeAssumedLibmediasoupDeviceBinding()
        let engine = MediaSFUAssumedLibmediasoupDeviceEngine(binding: binding)
        let backend = MediaSFUExpectedLibmediasoupDeviceBackend(engine: engine)
        let device = MediaSFULibmediasoupDeviceWrapper(backend: backend)
        let recv = try device.createRecvTransport(
            id: "assumed-recv",
            iceParametersJson: "{\"usernameFragment\":\"recv\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )
        let send = try device.createSendTransport(
            id: "assumed-send-2",
            iceParametersJson: "{\"usernameFragment\":\"send\"}",
            iceCandidatesJson: "[]",
            dtlsParametersJson: "{\"role\":\"auto\"}",
            sctpParametersJson: nil,
            appDataJson: nil
        )

        let consumer = try recv.consume(
            id: "assumed-consumer",
            producerId: "assumed-upstream",
            kind: "audio",
            rtpParametersJson: "{\"mid\":\"21\"}"
        )
        let producer = try send.produce(track: FakeTrack(), encodingsJson: nil, appDataJson: nil)
        try producer.replaceTrack(FakeTrack())
        producer.pause()
        producer.resume()

        XCTAssertEqual(consumer.id, "assumed-consumer")
        XCTAssertEqual(binding.recvTransport.lastConsumeOptions?.producerId, "assumed-upstream")
        XCTAssertEqual(binding.sendTransport.producerBinding.replaceTrackCount, 1)
        XCTAssertEqual(binding.sendTransport.producerBinding.pauseCount, 1)
        XCTAssertEqual(binding.sendTransport.producerBinding.resumeCount, 1)
    }

    func testRealMediasoupBindingEngineBuildsInstallableAdapter() throws {
        let binding = FakeAssumedLibmediasoupDeviceBinding()
        let adapter = RealMediasoupBindingEngine.makeInstallableAdapter(binding: binding)
        let send = try adapter.createSendTransport(params: validTransportParams(id: "real-send"))
        let recv = try adapter.createRecvTransport(params: validTransportParams(id: "real-recv"))

        XCTAssertEqual(send.id, "assumed-send")
        XCTAssertEqual(recv.id, "assumed-recv")
        XCTAssertEqual(RealMediasoupBindingIntegrationNotes.requiredSteps.count, 5)
    }

    func testConcreteMediasoupBindingTemplateBuildsInstallableAdapter() throws {
        let nativeDevice = FakeConcreteMediasoupNativeDevice()
        let adapter = ConcreteMediasoupBindingTemplate.makeInstallableAdapter(nativeDevice: nativeDevice)
        let send = try adapter.createSendTransport(params: validTransportParams(id: "concrete-send"))
        let recv = try adapter.createRecvTransport(params: validTransportParams(id: "concrete-recv"))

        XCTAssertEqual(send.id, "concrete-send")
        XCTAssertEqual(recv.id, "concrete-recv")

        let producer = try send.produce(track: FakeTrack(), encodingsJson: nil, appDataJson: "{\"source\":\"camera\"}")
        _ = try recv.consume(id: "concrete-consumer", producerId: "upstream-producer", kind: "video", rtpParametersJson: "{\"mid\":\"31\"}")
        try producer.replaceTrack(FakeTrack())

        XCTAssertEqual(nativeDevice.sendTransport.lastProduceOptions?.appDataJson, "{\"source\":\"camera\"}")
        XCTAssertEqual(nativeDevice.recvTransport.lastConsumeOptions?.producerId, "upstream-producer")
        XCTAssertEqual(nativeDevice.sendTransport.nativeProducer.replaceTrackCount, 1)
    }
}

private final class FakeDeviceAdapter: MediaSFUDeviceAdapter {
    let sendTransport = FakeSendTransportAdapter()
    let recvTransport = FakeRecvTransportAdapter()
    var lastSendParams: [String: Any?]?
    var lastRecvParams: [String: Any?]?

    func createSendTransport(params: [String : Any?]) throws -> MediaSFUSendTransportAdapter {
        lastSendParams = params
        return sendTransport
    }

    func createRecvTransport(params: [String : Any?]) throws -> MediaSFURecvTransportAdapter {
        lastRecvParams = params
        return recvTransport
    }
}

private class FakeBaseTransportAdapter: MediaSFUTransportAdapter {
    let id: String
    var connectionState: String = "new"
    var connectListener: MediaSFUNativeConnectListener?
    var stateListener: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
        stateListener?("closed")
    }

    func setOnConnect(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
    }

    func setOnConnectionStateChange(_ listener: ((String) -> Void)?) {
        stateListener = listener
    }

    func emitState(_ state: String) {
        connectionState = state
        stateListener?(state)
    }

    func emitConnect(dtlsJson: String) {
        connectListener?(dtlsJson, {}, { _ in })
    }
}

private final class FakeSendTransportAdapter: FakeBaseTransportAdapter, MediaSFUSendTransportAdapter {
    var produceListener: MediaSFUNativeProduceListener?
    var lastProducedTrack: MediaSFUNativeTrack?
    var lastProducedEncodingsJson: String?
    var lastProducedAppDataJson: String?

    init() {
        super.init(id: "send-adapter")
    }

    func setOnProduce(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
    }

    func produce(
        track: MediaSFUNativeTrack,
        encodingsJson: String?,
        appDataJson: String?
    ) throws -> MediaSFUProducerAdapter {
        lastProducedTrack = track
        lastProducedEncodingsJson = encodingsJson
        lastProducedAppDataJson = appDataJson

        var producerId = "producer-adapter"
        produceListener?("audio", "{}", appDataJson, { value in
            if let value {
                producerId = value
            }
        }, { _ in })

        return FakeProducerAdapter(id: producerId)
    }
}

private final class FakeRecvTransportAdapter: FakeBaseTransportAdapter, MediaSFURecvTransportAdapter {
    var lastConsumeId: String?
    var lastConsumeProducerId: String?
    var lastConsumeKind: String?
    var lastConsumeRtpJson: String?

    init() {
        super.init(id: "recv-adapter")
    }

    func consume(id: String, producerId: String, kind: String, rtpParametersJson: String) throws -> MediaSFUConsumerAdapter {
        lastConsumeId = id
        lastConsumeProducerId = producerId
        lastConsumeKind = kind
        lastConsumeRtpJson = rtpParametersJson
        return FakeConsumerAdapter(id: id, kind: kind, track: FakeTrack())
    }
}

private final class FakeProducerAdapter: MediaSFUProducerAdapter {
    let id: String
    let kind: String
    var paused = false

    init(id: String, kind: String = "audio") {
        self.id = id
        self.kind = kind
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws {}
    func getStatsJson() -> String? { nil }
}

private final class FakeConsumerAdapter: MediaSFUConsumerAdapter {
    let id: String
    let kind: String
    let track: MediaSFUNativeTrack?
    var paused = false

    init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func getStatsJson() -> String? { nil }
}

private func clientDeviceAdapter(_ clientDevice: FakeNativeClientDevice) -> ClientBackedDeviceAdapter {
    ClientBackedDeviceAdapter(clientDevice: clientDevice)
}

private func validTransportParams(id: String) -> [String: Any?] {
    [
        "id": id,
        "iceParameters": "{\"usernameFragment\":\"u1\"}",
        "iceCandidates": "[]",
        "dtlsParameters": "{\"role\":\"auto\"}",
        "appData": "{\"source\":\"camera\"}"
    ]
}

private final class FakeNativeClientDevice: MediaSFUNativeClientDevice {
    let sendTransport = FakeNativeClientSendTransport()
    let recvTransport = FakeNativeClientRecvTransport()
    var lastSendOptions: MediaSFUTransportCreationOptions?
    var lastRecvOptions: MediaSFUTransportCreationOptions?

    func createSendTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientSendTransport {
        lastSendOptions = options
        return sendTransport
    }

    func createRecvTransport(options: MediaSFUTransportCreationOptions) throws -> MediaSFUNativeClientRecvTransport {
        lastRecvOptions = options
        return recvTransport
    }
}

private class FakeNativeClientBaseTransport: MediaSFUNativeClientTransport {
    let id: String
    var connectionState: String = "new"
    var connectListener: MediaSFUNativeConnectListener?
    var stateListener: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
    }

    func onConnect(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
    }

    func onConnectionStateChange(_ listener: ((String) -> Void)?) {
        stateListener = listener
    }
}

private final class FakeNativeClientSendTransport: FakeNativeClientBaseTransport, MediaSFUNativeClientSendTransport {
    var produceListener: MediaSFUNativeProduceListener?
    var lastProduceTrack: MediaSFUNativeTrack?
    var lastProduceOptions: MediaSFUProduceOptions?

    init() {
        super.init(id: "native-send")
    }

    func onProduce(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
    }

    func produce(track: MediaSFUNativeTrack, options: MediaSFUProduceOptions) throws -> MediaSFUNativeClientProducer {
        lastProduceTrack = track
        lastProduceOptions = options
        return FakeNativeClientProducer(id: "native-producer")
    }
}

private final class FakeNativeClientRecvTransport: FakeNativeClientBaseTransport, MediaSFUNativeClientRecvTransport {
    var lastConsumeOptions: MediaSFUConsumeOptions?

    init() {
        super.init(id: "native-recv")
    }

    func consume(options: MediaSFUConsumeOptions) throws -> MediaSFUNativeClientConsumer {
        lastConsumeOptions = options
        return FakeNativeClientConsumer(id: options.id, kind: options.kind, track: FakeTrack())
    }
}

private final class FakeNativeClientProducer: MediaSFUNativeClientProducer {
    let id: String
    let kind: String
    var paused = false

    init(id: String, kind: String = "video") {
        self.id = id
        self.kind = kind
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws {}
    func getStatsJson() -> String? { nil }
}

private final class FakeNativeClientConsumer: MediaSFUNativeClientConsumer {
    let id: String
    let kind: String
    let track: MediaSFUNativeTrack?
    var paused = false

    init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func getStatsJson() -> String? { nil }
}

private final class FakeLibmediasoupDevice: MediaSFULibmediasoupDevice {
    let sendTransport = FakeLibmediasoupSendTransport()
    let recvTransport = FakeLibmediasoupRecvTransport()
    var lastSendId: String?
    var lastSendIceParametersJson: String?
    var lastSendIceCandidatesJson: String?
    var lastSendDtlsParametersJson: String?
    var lastSendSctpParametersJson: String?
    var lastSendAppDataJson: String?

    func createSendTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupSendTransport {
        lastSendId = id
        lastSendIceParametersJson = iceParametersJson
        lastSendIceCandidatesJson = iceCandidatesJson
        lastSendDtlsParametersJson = dtlsParametersJson
        lastSendSctpParametersJson = sctpParametersJson
        lastSendAppDataJson = appDataJson
        return sendTransport
    }

    func createRecvTransport(
        id: String,
        iceParametersJson: String,
        iceCandidatesJson: String,
        dtlsParametersJson: String,
        sctpParametersJson: String?,
        appDataJson: String?
    ) throws -> MediaSFULibmediasoupRecvTransport {
        _ = id
        _ = iceParametersJson
        _ = iceCandidatesJson
        _ = dtlsParametersJson
        _ = sctpParametersJson
        _ = appDataJson
        return recvTransport
    }
}

private class FakeLibmediasoupBaseTransport: MediaSFULibmediasoupTransport {
    let id: String
    var connectionState: String = "new"
    var connectListener: MediaSFUNativeConnectListener?
    var stateListener: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
    }

    func onConnect(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
    }

    func onConnectionStateChange(_ listener: ((String) -> Void)?) {
        stateListener = listener
    }

    func emitState(_ state: String) {
        connectionState = state
        stateListener?(state)
    }
}

private final class FakeLibmediasoupSendTransport: FakeLibmediasoupBaseTransport, MediaSFULibmediasoupSendTransport {
    var produceListener: MediaSFUNativeProduceListener?
    var lastEncodingsJson: String?
    var lastAppDataJson: String?

    init() {
        super.init(id: "lib-send")
    }

    func onProduce(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
    }

    func produce(track: MediaSFUNativeTrack, encodingsJson: String?, appDataJson: String?) throws -> MediaSFULibmediasoupProducer {
        _ = track
        lastEncodingsJson = encodingsJson
        lastAppDataJson = appDataJson
        return FakeLibmediasoupProducer(id: "lib-producer")
    }
}

private final class FakeLibmediasoupRecvTransport: FakeLibmediasoupBaseTransport, MediaSFULibmediasoupRecvTransport {
    var lastConsumedId: String?
    var lastConsumedProducerId: String?
    var lastConsumedKind: String?
    var lastConsumedRtpParametersJson: String?

    init() {
        super.init(id: "lib-recv")
    }

    func consume(
        id: String,
        producerId: String,
        kind: String,
        rtpParametersJson: String
    ) throws -> MediaSFULibmediasoupConsumer {
        lastConsumedId = id
        lastConsumedProducerId = producerId
        lastConsumedKind = kind
        lastConsumedRtpParametersJson = rtpParametersJson
        return FakeLibmediasoupConsumer(id: id, kind: kind, track: FakeTrack())
    }
}

private final class FakeLibmediasoupProducer: MediaSFULibmediasoupProducer {
    let id: String
    let kind: String
    var paused = false

    init(id: String, kind: String = "video") {
        self.id = id
        self.kind = kind
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws { _ = track }
    func getStatsJson() -> String? { nil }
}

private final class FakeLibmediasoupConsumer: MediaSFULibmediasoupConsumer {
    let id: String
    let kind: String
    let track: MediaSFUNativeTrack?
    var paused = false

    init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func getStatsJson() -> String? { nil }
}

private final class FakeRawLibmediasoupDeviceBackend: MediaSFURawLibmediasoupDeviceBackend {
    let sendBackend = FakeRawLibmediasoupSendTransportBackend()
    let recvBackend = FakeRawLibmediasoupRecvTransportBackend()
    var lastSendOptions: MediaSFURawTransportOptions?
    var lastRecvOptions: MediaSFURawTransportOptions?

    func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupSendTransportBackend {
        lastSendOptions = options
        return sendBackend
    }

    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFURawLibmediasoupRecvTransportBackend {
        lastRecvOptions = options
        return recvBackend
    }
}

private class FakeRawLibmediasoupBaseTransportBackend: MediaSFURawLibmediasoupTransportBackend {
    let id: String
    var connectionState: String = "new"
    var connectListener: MediaSFUNativeConnectListener?
    var stateListener: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
    }

    func setConnectListener(_ listener: MediaSFUNativeConnectListener?) {
        connectListener = listener
    }

    func setConnectionStateListener(_ listener: ((String) -> Void)?) {
        stateListener = listener
    }

    func emitState(_ state: String) {
        connectionState = state
        stateListener?(state)
    }
}

private final class FakeRawLibmediasoupSendTransportBackend: FakeRawLibmediasoupBaseTransportBackend, MediaSFURawLibmediasoupSendTransportBackend {
    var produceListener: MediaSFUNativeProduceListener?
    var lastProduceOptions: MediaSFURawProduceOptions?

    init() {
        super.init(id: "raw-send")
    }

    func setProduceListener(_ listener: MediaSFUNativeProduceListener?) {
        produceListener = listener
    }

    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend {
        _ = track
        lastProduceOptions = options
        return FakeRawLibmediasoupProducerBackend(id: "raw-producer")
    }
}

private final class FakeRawLibmediasoupRecvTransportBackend: FakeRawLibmediasoupBaseTransportBackend, MediaSFURawLibmediasoupRecvTransportBackend {
    var lastConsumeOptions: MediaSFURawConsumeOptions?

    init() {
        super.init(id: "raw-recv")
    }

    func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend {
        lastConsumeOptions = options
        return FakeRawLibmediasoupConsumerBackend(id: options.id, kind: options.kind, track: FakeTrack())
    }
}

private final class FakeRawLibmediasoupProducerBackend: MediaSFURawLibmediasoupProducerBackend {
    let id: String
    let kind: String
    var paused = false

    init(id: String, kind: String = "video") {
        self.id = id
        self.kind = kind
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws { _ = track }
    func getStatsJson() -> String? { nil }
}

private final class FakeRawLibmediasoupConsumerBackend: MediaSFURawLibmediasoupConsumerBackend {
    let id: String
    let kind: String
    let track: MediaSFUNativeTrack?
    var paused = false

    init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func getStatsJson() -> String? { nil }
}

private final class FakeExpectedLibmediasoupDeviceEngine: MediaSFUExpectedLibmediasoupDeviceEngine {
    let sendTransport = FakeExpectedLibmediasoupSendTransportEngine()
    let recvTransport = FakeExpectedLibmediasoupRecvTransportEngine()

    func createSendTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupSendTransportEngine {
        _ = options
        return sendTransport
    }

    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> MediaSFUExpectedLibmediasoupRecvTransportEngine {
        _ = options
        return recvTransport
    }
}

private class FakeExpectedLibmediasoupBaseTransportEngine: MediaSFUExpectedLibmediasoupTransportEngine {
    let id: String
    var connectionState: String = "new"
    var stateObserver: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
    }

    func setConnectionStateObserver(_ observer: ((String) -> Void)?) {
        stateObserver = observer
    }

    func emitState(_ state: String) {
        connectionState = state
        stateObserver?(state)
    }
}

private final class FakeExpectedLibmediasoupSendTransportEngine: FakeExpectedLibmediasoupBaseTransportEngine, MediaSFUExpectedLibmediasoupSendTransportEngine {
    var connectHandler: MediaSFUNativeConnectListener?
    var produceHandler: MediaSFUNativeProduceListener?
    var lastProduceOptions: MediaSFURawProduceOptions?

    init() {
        super.init(id: "expected-send")
    }

    func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func setProduceRequestHandler(_ handler: MediaSFUNativeProduceListener?) {
        produceHandler = handler
    }

    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFURawLibmediasoupProducerBackend {
        _ = track
        lastProduceOptions = options
        return FakeRawLibmediasoupProducerBackend(id: "expected-producer")
    }

    func emitConnect(dtlsJson: String) {
        connectHandler?(dtlsJson, {}, { _ in })
    }
}

private final class FakeExpectedLibmediasoupRecvTransportEngine: FakeExpectedLibmediasoupBaseTransportEngine, MediaSFUExpectedLibmediasoupRecvTransportEngine {
    var connectHandler: MediaSFUNativeConnectListener?
    var lastConsumeOptions: MediaSFURawConsumeOptions?

    init() {
        super.init(id: "expected-recv")
    }

    func setConnectRequestHandler(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func consume(options: MediaSFURawConsumeOptions) throws -> MediaSFURawLibmediasoupConsumerBackend {
        lastConsumeOptions = options
        return FakeRawLibmediasoupConsumerBackend(id: options.id, kind: options.kind, track: FakeTrack())
    }
}

private final class FakeAssumedLibmediasoupDeviceBinding: MediaSFUAssumedLibmediasoupDeviceBinding {
    let sendTransport = FakeAssumedLibmediasoupSendTransportBinding()
    let recvTransport = FakeAssumedLibmediasoupRecvTransportBinding()

    func makeSendTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupSendTransportBinding {
        _ = config
        return sendTransport
    }

    func makeRecvTransport(config: MediaSFURawTransportOptions) throws -> MediaSFUAssumedLibmediasoupRecvTransportBinding {
        _ = config
        return recvTransport
    }
}

private class FakeAssumedLibmediasoupBaseTransportBinding: MediaSFUAssumedLibmediasoupTransportBinding {
    let identifier: String
    var state: String = "new"
    var stateObserver: ((String) -> Void)?

    init(identifier: String) {
        self.identifier = identifier
    }

    func shutdown() {
        state = "closed"
    }

    func observeState(_ observer: ((String) -> Void)?) {
        stateObserver = observer
    }

    func emitState(_ state: String) {
        self.state = state
        stateObserver?(state)
    }
}

private final class FakeAssumedLibmediasoupSendTransportBinding: FakeAssumedLibmediasoupBaseTransportBinding, MediaSFUAssumedLibmediasoupSendTransportBinding {
    var connectHandler: MediaSFUNativeConnectListener?
    var produceHandler: MediaSFUNativeProduceListener?
    var lastProduceOptions: MediaSFURawProduceOptions?
    let producerBinding = FakeAssumedLibmediasoupProducerBinding(identifier: "assumed-producer")

    init() {
        super.init(identifier: "assumed-send")
    }

    func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func onProduceNeeded(_ handler: MediaSFUNativeProduceListener?) {
        produceHandler = handler
    }

    func startProducing(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> MediaSFUAssumedLibmediasoupProducerBinding {
        _ = track
        lastProduceOptions = options
        return producerBinding
    }

    func emitConnect(dtlsJson: String) {
        connectHandler?(dtlsJson, {}, { _ in })
    }
}

private final class FakeAssumedLibmediasoupRecvTransportBinding: FakeAssumedLibmediasoupBaseTransportBinding, MediaSFUAssumedLibmediasoupRecvTransportBinding {
    var connectHandler: MediaSFUNativeConnectListener?
    var lastConsumeOptions: MediaSFURawConsumeOptions?

    init() {
        super.init(identifier: "assumed-recv")
    }

    func onConnectNeeded(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func startConsuming(options: MediaSFURawConsumeOptions) throws -> MediaSFUAssumedLibmediasoupConsumerBinding {
        lastConsumeOptions = options
        return FakeAssumedLibmediasoupConsumerBinding(identifier: options.id, mediaKind: options.kind, mediaTrack: FakeTrack())
    }
}

private final class FakeAssumedLibmediasoupProducerBinding: MediaSFUAssumedLibmediasoupProducerBinding {
    let identifier: String
    let mediaKind: String
    var isCurrentlyPaused = false
    var replaceTrackCount = 0
    var pauseCount = 0
    var resumeCount = 0

    init(identifier: String, mediaKind: String = "video") {
        self.identifier = identifier
        self.mediaKind = mediaKind
    }

    func shutdown() {}
    func pauseSending() { isCurrentlyPaused = true; pauseCount += 1 }
    func resumeSending() { isCurrentlyPaused = false; resumeCount += 1 }
    func updateTrack(_ track: MediaSFUNativeTrack) throws {
        _ = track
        replaceTrackCount += 1
    }
    func getStatsJson() -> String? { nil }
}

private final class FakeAssumedLibmediasoupConsumerBinding: MediaSFUAssumedLibmediasoupConsumerBinding {
    let identifier: String
    let mediaKind: String
    let mediaTrack: MediaSFUNativeTrack?
    var isCurrentlyPaused = false

    init(identifier: String, mediaKind: String, mediaTrack: MediaSFUNativeTrack?) {
        self.identifier = identifier
        self.mediaKind = mediaKind
        self.mediaTrack = mediaTrack
    }

    func shutdown() {}
    func pauseReceiving() { isCurrentlyPaused = true }
    func resumeReceiving() { isCurrentlyPaused = false }
    func getStatsJson() -> String? { nil }
}

private final class FakeConcreteMediasoupNativeDevice: ConcreteMediasoupNativeDevice {
    let sendTransport = FakeConcreteMediasoupNativeSendTransport(id: "concrete-send")
    let recvTransport = FakeConcreteMediasoupNativeRecvTransport(id: "concrete-recv")
    var loadedRtpCapabilitiesJson: String?

    func load(routerRtpCapabilitiesJson: String) throws {
        loadedRtpCapabilitiesJson = routerRtpCapabilitiesJson
    }

    func rtpCapabilitiesJson() throws -> String? {
        loadedRtpCapabilitiesJson
    }

    func createSendTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeSendTransport {
        _ = options
        return sendTransport
    }

    func createRecvTransport(options: MediaSFURawTransportOptions) throws -> ConcreteMediasoupNativeRecvTransport {
        _ = options
        return recvTransport
    }
}

private class FakeConcreteMediasoupNativeBaseTransport: ConcreteMediasoupNativeTransport {
    let id: String
    var connectionState: String = "new"
    var stateHandler: ((String) -> Void)?

    init(id: String) {
        self.id = id
    }

    func close() {
        connectionState = "closed"
    }

    func setConnectionStateHandler(_ handler: ((String) -> Void)?) {
        stateHandler = handler
    }
}

private final class FakeConcreteMediasoupNativeSendTransport: FakeConcreteMediasoupNativeBaseTransport, ConcreteMediasoupNativeSendTransport {
    var connectHandler: MediaSFUNativeConnectListener?
    var produceHandler: MediaSFUNativeProduceListener?
    var lastProduceOptions: MediaSFURawProduceOptions?
    let nativeProducer = FakeConcreteMediasoupNativeProducer(id: "concrete-producer")

    func setConnectHandler(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func setProduceHandler(_ handler: MediaSFUNativeProduceListener?) {
        produceHandler = handler
    }

    func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> ConcreteMediasoupNativeProducer {
        _ = track
        lastProduceOptions = options
        return nativeProducer
    }
}

private final class FakeConcreteMediasoupNativeRecvTransport: FakeConcreteMediasoupNativeBaseTransport, ConcreteMediasoupNativeRecvTransport {
    var connectHandler: MediaSFUNativeConnectListener?
    var lastConsumeOptions: MediaSFURawConsumeOptions?

    func setConnectHandler(_ handler: MediaSFUNativeConnectListener?) {
        connectHandler = handler
    }

    func consume(options: MediaSFURawConsumeOptions) throws -> ConcreteMediasoupNativeConsumer {
        lastConsumeOptions = options
        return FakeConcreteMediasoupNativeConsumer(id: options.id, kind: options.kind, track: FakeTrack())
    }
}

private final class FakeConcreteMediasoupNativeProducer: ConcreteMediasoupNativeProducer {
    let id: String
    let kind: String
    var paused = false
    var replaceTrackCount = 0

    init(id: String, kind: String = "video") {
        self.id = id
        self.kind = kind
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func replaceTrack(_ track: MediaSFUNativeTrack) throws {
        _ = track
        replaceTrackCount += 1
    }
    func getStatsJson() -> String? { nil }
}

private final class FakeConcreteMediasoupNativeConsumer: ConcreteMediasoupNativeConsumer {
    let id: String
    let kind: String
    let track: MediaSFUNativeTrack?
    var paused = false

    init(id: String, kind: String, track: MediaSFUNativeTrack?) {
        self.id = id
        self.kind = kind
        self.track = track
    }

    func close() {}
    func pause() { paused = true }
    func resume() { paused = false }
    func getStatsJson() -> String? { nil }
}

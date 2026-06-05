import Foundation

#if canImport(MediaSFUMediasoupClient)
import MediaSFUMediasoupClient

public enum MediaSFUMediasoupClientBridgeFactory {
    public static func makeInstallableAdapter(device: MSCDevice) -> MediaSFUDeviceAdapter {
        let concreteDevice = MediaSFUMediasoupClientConcreteDevice(device: device)
        let adapter = ConcreteMediasoupBindingTemplate.makeInstallableAdapter(nativeDevice: concreteDevice)
        return MediaSFUMediasoupClientLoadableAdapter(device: device, adapter: adapter)
    }
}

private final class MediaSFUMediasoupClientLoadableAdapter: MediaSFUDeviceAdapter, MediaSFULoadableDeviceAdapter, MediaSFUCurrentRtpCapabilitiesProvider {
    private let device: MSCDevice
    private let adapter: MediaSFUDeviceAdapter

    init(device: MSCDevice, adapter: MediaSFUDeviceAdapter) {
        self.device = device
        self.adapter = adapter
    }

    func load(routerRtpCapabilitiesJson: String) throws {
        let sanitizedJson = sanitizeRouterRtpCapabilitiesJson(routerRtpCapabilitiesJson)
        NSLog("[MediaSFUIosBridge] Loading device with sanitized JSON (len=%d): %@",
              sanitizedJson.count,
              sanitizedJson.count > 2000 ? String(sanitizedJson.prefix(2000)) + "...(truncated)" : sanitizedJson)
        do {
            try device.load(routerRtpCapabilitiesJson: sanitizedJson)
            NSLog("[MediaSFUIosBridge] Device loaded successfully")
        } catch {
            let message = String(describing: error).lowercased()
            NSLog("[MediaSFUIosBridge] Device load error: %@", String(describing: error))
            if message.contains("already loaded") {
                return
            }
            guard
                message.contains("invalid codec apt parameter") ||
                message.contains("invalid ext.kind") ||
                message.contains("type_error")
            else {
                throw error
            }

            throw error
        }
    }

    func createSendTransport(params: [String : Any?]) throws -> MediaSFUSendTransportAdapter {
        try adapter.createSendTransport(params: params)
    }

    func createRecvTransport(params: [String : Any?]) throws -> MediaSFURecvTransportAdapter {
        try adapter.createRecvTransport(params: params)
    }

    func currentRtpCapabilitiesJson() -> String? {
        try? device.rtpCapabilitiesJson()
    }

    private func sanitizeRouterRtpCapabilitiesJson(_ json: String) -> String {
        guard
            let data = json.data(using: .utf8),
            var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            var codecs = payload["codecs"] as? [[String: Any]]
        else {
            return json
        }

        var changed = false
        if let normalizedPayload = normalizeRtcpFeedback(in: payload, changed: &changed) as? [String: Any] {
            payload = normalizedPayload
            codecs = payload["codecs"] as? [[String: Any]] ?? codecs
        }

        let validPayloadTypes = Set(codecs.compactMap { codec -> Int? in
            if let pt = codec["preferredPayloadType"] as? Int { return pt }
            if let pt = codec["preferredPayloadType"] as? NSNumber { return pt.intValue }
            if let pt = codec["preferredPayloadType"] as? String { return Int(pt) }
            return nil
        })

        for index in codecs.indices {
            guard var parameters = codecs[index]["parameters"] as? [String: Any] else { continue }
            guard let aptValue = parameters["apt"] else { continue }

            let aptInt: Int? = {
                if let value = aptValue as? Int { return value }
                if let value = aptValue as? NSNumber { return value.intValue }
                if let value = aptValue as? String { return Int(value) }
                return nil
            }()

            if let apt = aptInt, validPayloadTypes.contains(apt) {
                if (aptValue as? Int) != apt {
                    parameters["apt"] = apt
                    codecs[index]["parameters"] = parameters
                    changed = true
                }
                continue
            }

            parameters.removeValue(forKey: "apt")
            codecs[index]["parameters"] = parameters
            changed = true
        }

        if let headerExtensions = payload["headerExtensions"] as? [[String: Any]] {
            var normalizedHeaderExtensions: [[String: Any]] = []
            normalizedHeaderExtensions.reserveCapacity(headerExtensions.count)

            for var entry in headerExtensions {
                guard let rawKind = entry["kind"] as? String else {
                    changed = true
                    continue
                }

                let normalizedKind = rawKind.lowercased()
                guard normalizedKind == "audio" || normalizedKind == "video" else {
                    changed = true
                    continue
                }

                if rawKind != normalizedKind {
                    entry["kind"] = normalizedKind
                    changed = true
                }

                normalizedHeaderExtensions.append(entry)
            }

            if normalizedHeaderExtensions.count != headerExtensions.count || changed {
                payload["headerExtensions"] = normalizedHeaderExtensions
            }
        }

        guard changed else { return json }
        payload["codecs"] = codecs

        guard
            let sanitizedData = try? JSONSerialization.data(withJSONObject: payload),
            let sanitizedJson = String(data: sanitizedData, encoding: .utf8)
        else {
            return json
        }
        return sanitizedJson
    }

    private func normalizeRtcpFeedback(in value: Any, changed: inout Bool) -> Any {
        if let dictionary = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            normalized.reserveCapacity(dictionary.count)

            for (key, childValue) in dictionary {
                if key == "rtcpFeedback" {
                    normalized[key] = normalizeRtcpFeedbackArray(childValue, changed: &changed)
                } else {
                    normalized[key] = normalizeRtcpFeedback(in: childValue, changed: &changed)
                }
            }

            return normalized
        }

        if let array = value as? [Any] {
            return array.map { normalizeRtcpFeedback(in: $0, changed: &changed) }
        }

        return value
    }

    private func normalizeRtcpFeedbackArray(_ value: Any, changed: inout Bool) -> [Any] {
        guard let entries = value as? [Any] else {
            changed = true
            return []
        }

        var normalizedEntries: [Any] = []
        normalizedEntries.reserveCapacity(entries.count)

        for case var entry as [String: Any] in entries {
            let typeValue = entry["type"]
            let typeString = (typeValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let normalizedType = typeString, !normalizedType.isEmpty else {
                changed = true
                continue
            }

            if (typeValue as? String) != normalizedType {
                entry["type"] = normalizedType
                changed = true
            }

            if let parameterValue = entry["parameter"] {
                if parameterValue is NSNull {
                    entry["parameter"] = ""
                    changed = true
                } else if let parameterString = parameterValue as? String {
                    let normalizedParameter = parameterString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if parameterString != normalizedParameter {
                        entry["parameter"] = normalizedParameter
                        changed = true
                    }
                } else {
                    entry["parameter"] = String(describing: parameterValue)
                    changed = true
                }
            }

            normalizedEntries.append(entry)
        }

        if normalizedEntries.count != entries.count {
            changed = true
        }

        return normalizedEntries
    }
}

public final class MediaSFUMediasoupClientConcreteDevice: ConcreteMediasoupNativeDevice {
    private let device: MSCDevice

    public init(device: MSCDevice) {
        self.device = device
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
        guard let handler = handler else {
            transport.setConnectHandler(nil)
            return
        }
        // The ObjC mediasoupclient wrapper calls the connect handler synchronously
        // and immediately checks that callback() was invoked before returning.
        // Kotlin's onConnect dispatches work on a background coroutine and returns
        // immediately, so we must block here until the async callback fires.
        transport.setConnectHandler { dtlsParametersJson, callback, errback in
            let sema = DispatchSemaphore(value: 0)
            handler(dtlsParametersJson, {
                callback()
                sema.signal()
            }, { error in
                errback(error)
                sema.signal()
            })
            sema.wait()
        }
    }
    public func setProduceHandler(_ handler: MediaSFUNativeProduceListener?) {
        guard let handler = handler else {
            transport.setProduceHandler(nil)
            return
        }
        // Same synchronous ObjC check as the connect handler — wrap with semaphore
        // so the Kotlin async socket round-trip (onProduce) can complete before
        // the ObjC layer checks that callback() was invoked.
        transport.setProduceHandler { kind, rtpParametersJson, appDataJson, callback, errback in
            let sema = DispatchSemaphore(value: 0)
            handler(kind, rtpParametersJson, appDataJson, { producerId in
                callback(producerId)
                sema.signal()
            }, { error in
                errback(error)
                sema.signal()
            })
            sema.wait()
        }
    }

    public func produce(track: MediaSFUNativeTrack, options: MediaSFURawProduceOptions) throws -> ConcreteMediasoupNativeProducer {
        guard let nativeTrack = track as? MSCNativeTrack else {
            throw MSCError.unsupportedTrackType
        }
        let encodingsJson = options.encodingsJson ?? "[]"
        let codecOptionsJson = options.codecOptionsJson
        let codecJson = options.codecJson
        let appDataJson = options.appDataJson ?? "{}"
        let producer = try transport.produce(
            track: nativeTrack,
            encodingsJson: encodingsJson,
            codecOptionsJson: codecOptionsJson,
            codecJson: codecJson,
            appDataJson: appDataJson
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

    public func replaceTrack(_ track: MediaSFUNativeTrack) throws {
        guard let nativeTrack = track as? MSCNativeTrack else {
            throw MSCError.unsupportedTrackType
        }
        try producer.replaceTrack(nativeTrack)
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
}
#endif

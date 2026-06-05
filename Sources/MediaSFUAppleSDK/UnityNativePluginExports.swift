import Foundation

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient)
import MediaSFUMediasoupClient
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

#if os(macOS)
import CoreGraphics
import CoreVideo
#endif

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC
#endif

final class MediaSFUIosUnityNativePluginEngine {
    let host: MediaSFUIosUnityWebRtcOperationHost

    init(host: MediaSFUIosUnityWebRtcOperationHost) {
        self.host = host
    }
}

enum MediaSFUIosUnityNativePluginFactory {
    typealias EngineBuilder = (_ createPayloadJson: String) throws -> MediaSFUIosUnityNativePluginEngine

    private static let lock = NSLock()
    private static var overrideBuilder: EngineBuilder?

    static func makeEngine(createPayloadJson: String) throws -> MediaSFUIosUnityNativePluginEngine {
        if let builder = currentOverrideBuilder() {
            return try builder(createPayloadJson)
        }

        return try defaultBuilder(createPayloadJson)
    }

    static func installOverrideBuilder(_ builder: EngineBuilder?) {
        lock.lock()
        overrideBuilder = builder
        lock.unlock()
    }

    private static func currentOverrideBuilder() -> EngineBuilder? {
        lock.lock()
        defer { lock.unlock() }
        return overrideBuilder
    }

    private static func defaultBuilder(_ createPayloadJson: String) throws -> MediaSFUIosUnityNativePluginEngine {
        _ = try parseCreatePayload(createPayloadJson)

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient) && MSC_HAVE_REAL_LIBMEDIASOUPCLIENT_BINDING
        let device = MSCDevice()
        guard device.nativeIntegrationMode != .stubBacked else {
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin requires bundled mediasoup/WebRTC native artifacts. Current mode: \(device.nativeIntegrationMode.rawValue). \(MSCNativeIntegrationStatus.summary) \(MSCNativeBinaryStatus.summary)"
            )
        }

        guard let peerConnectionFactory = device.peerConnectionFactory() else {
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin could not resolve the mediasoup peer connection factory needed for local track production."
            )
        }

        let adapter = MediaSFUMediasoupClientBridgeFactory.makeInstallableAdapter(device: device)
        let localTrackFactory = MediaSFUIosUnityDefaultLocalTrackFactory(factory: peerConnectionFactory)
        let host = MediaSFUIosUnityWebRtcOperationHost(
            device: adapter,
            trackFactory: localTrackFactory.makeTrackResource(for:)
        )
        return MediaSFUIosUnityNativePluginEngine(host: host)
#elseif MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(MediaSFUMediasoupClient)
        throw MediaSFUUnityNativePluginError(
            "MediaSFU Unity native plugin requires real mediasoup/WebRTC native artifacts. " +
            "Rebuild with MSC_HAVE_REAL_LIBMEDIASOUPCLIENT_BINDING=1 and the bundled XCFrameworks."
        )
#else
        throw MediaSFUUnityNativePluginError(
            "MediaSFU Unity native plugin requires the MediaSFUMediasoupClient package to be linked into this build."
        )
#endif
    }

    private static func parseCreatePayload(_ createPayloadJson: String) throws -> [String: Any] {
        guard let json = createPayloadJson.takeUnlessBlank() else {
            return [:]
        }

        do {
            return try MediaSFUBridgeJson.decodeObject(json)
        } catch {
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin received an invalid create-engine payload: \(error.localizedDescription)"
            )
        }
    }
}

struct MediaSFUUnityNativePluginError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC) && canImport(AVFoundation)
#if os(macOS)
private final class MediaSFUIosUnityMacOSDisplayCapturer: RTCVideoCapturer {
    private let videoSource: RTCVideoSource
    private let displayId: CGDirectDisplayID
    private let targetWidth: Int
    private let targetHeight: Int
    private let frameRate: Int
    private let captureQueue = DispatchQueue(label: "com.mediasfu.ios.unity.native-plugin.screen-capture")
    private let stateLock = NSLock()

    private var timer: DispatchSourceTimer?
    private var started = false

    init(
        videoSource: RTCVideoSource,
        displayId: CGDirectDisplayID,
        targetWidth: Int,
        targetHeight: Int,
        frameRate: Int
    ) {
        self.videoSource = videoSource
        self.displayId = displayId
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.frameRate = frameRate
        super.init(delegate: videoSource)
    }

    func start() throws {
        stateLock.lock()
        if started {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        guard let firstFrame = makeFrame() else {
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin could not capture the main display. Grant Screen Recording access to Unity or the hosting process in System Settings > Privacy & Security > Screen Recording."
            )
        }

        videoSource.adaptOutputFormat(
            toWidth: Int32(targetWidth),
            height: Int32(targetHeight),
            fps: Int32(frameRate)
        )
        videoSource.capturer(self, didCapture: firstFrame)

        let intervalMs = max(1000 / max(frameRate, 1), 1)
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMs),
            repeating: .milliseconds(intervalMs),
            leeway: .milliseconds(max(intervalMs / 4, 1))
        )
        timer.setEventHandler { [weak self] in
            self?.captureFrame()
        }

        stateLock.lock()
        self.timer = timer
        started = true
        stateLock.unlock()

        timer.activate()
    }

    func stop() {
        stateLock.lock()
        let timer = self.timer
        self.timer = nil
        started = false
        stateLock.unlock()

        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func captureFrame() {
        guard let frame = makeFrame() else {
            return
        }

        videoSource.capturer(self, didCapture: frame)
    }

    private func makeFrame() -> RTCVideoFrame? {
        guard let cgImage = CGDisplayCreateImage(displayId) else {
            return nil
        }

        guard let pixelBuffer = createPixelBuffer(width: targetWidth, height: targetHeight) else {
            return nil
        }

        guard drawImage(cgImage, into: pixelBuffer, width: targetWidth, height: targetHeight) else {
            return nil
        }

        guard let rotation = RTCVideoRotation(rawValue: 0) else {
            return nil
        }

        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        return RTCVideoFrame(
            buffer: buffer,
            rotation: rotation,
            timeStampNs: Int64(DispatchTime.now().uptimeNanoseconds)
        )
    }

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    private func drawImage(
        _ cgImage: CGImage,
        into pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return false
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
}

private final class MediaSFUIosUnitySyntheticVideoCapturer: RTCVideoCapturer {
    private let videoSource: RTCVideoSource
    private let targetWidth: Int
    private let targetHeight: Int
    private let frameRate: Int
    private let captureQueue = DispatchQueue(label: "com.mediasfu.ios.unity.native-plugin.synthetic-camera")
    private let stateLock = NSLock()

    private var timer: DispatchSourceTimer?
    private var started = false
    private var frameIndex: Int64 = 0

    init(videoSource: RTCVideoSource, targetWidth: Int, targetHeight: Int, frameRate: Int) {
        self.videoSource = videoSource
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        self.frameRate = frameRate
        super.init(delegate: videoSource)
    }

    func start() {
        stateLock.lock()
        if started {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        videoSource.adaptOutputFormat(
            toWidth: Int32(targetWidth),
            height: Int32(targetHeight),
            fps: Int32(frameRate)
        )
        captureFrame()

        let intervalMs = max(1000 / max(frameRate, 1), 1)
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(intervalMs),
            repeating: .milliseconds(intervalMs),
            leeway: .milliseconds(max(intervalMs / 4, 1))
        )
        timer.setEventHandler { [weak self] in
            self?.captureFrame()
        }

        stateLock.lock()
        self.timer = timer
        stateLock.unlock()

        timer.activate()
    }

    func stop() {
        stateLock.lock()
        let timer = self.timer
        self.timer = nil
        started = false
        stateLock.unlock()

        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func captureFrame() {
        guard let frame = makeFrame() else {
            return
        }

        videoSource.capturer(self, didCapture: frame)
    }

    private func makeFrame() -> RTCVideoFrame? {
        guard let pixelBuffer = createPixelBuffer(width: targetWidth, height: targetHeight) else {
            return nil
        }

        frameIndex += 1
        guard drawPattern(into: pixelBuffer, width: targetWidth, height: targetHeight, frameIndex: frameIndex) else {
            return nil
        }

        guard let rotation = RTCVideoRotation(rawValue: 0) else {
            return nil
        }

        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        return RTCVideoFrame(
            buffer: buffer,
            rotation: rotation,
            timeStampNs: Int64(DispatchTime.now().uptimeNanoseconds)
        )
    }

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    private func drawPattern(
        into pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        frameIndex: Int64
    ) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return false
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return false
        }

        let phase = CGFloat(frameIndex % 180) / 180.0
        context.setFillColor(CGColor(red: 0.08 + 0.32 * phase, green: 0.18, blue: 0.55 - 0.22 * phase, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let stripeHeight = max(height / 6, 24)
        let stripeOffset = Int((frameIndex * 7) % Int64(max(height, 1)))
        context.setFillColor(CGColor(red: 0.95, green: 0.78, blue: 0.18, alpha: 1.0))
        context.fill(CGRect(x: 0, y: stripeOffset - stripeHeight / 2, width: width, height: stripeHeight))

        let boxSize = max(min(width, height) / 5, 48)
        let horizontalRange = max(width - boxSize, 1)
        let verticalRange = max(height - boxSize, 1)
        let boxX = Int((frameIndex * 11) % Int64(horizontalRange))
        let boxY = Int((frameIndex * 5) % Int64(verticalRange))
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0))
        context.fill(CGRect(x: boxX, y: boxY, width: boxSize, height: boxSize))

        let markerWidth = max(width / 10, 20)
        context.setFillColor(CGColor(red: 0.12, green: 0.88, blue: 0.78, alpha: 1.0))
        context.fill(CGRect(x: width - markerWidth, y: 0, width: markerWidth, height: height))

        return true
    }
}
#endif

final class MediaSFUIosUnityDefaultLocalTrackFactory {
    private static let cameraWidth = 1280
    private static let cameraHeight = 720
    private static let cameraFrameRate = 30
    private static let syntheticCameraFrameRate = 12
    private static let screenMaxWidth = 1280
    private static let screenMaxHeight = 720
    private static let screenFrameRate = 10

    private let factory: RTCPeerConnectionFactory
    private let captureQueue = DispatchQueue(label: "com.mediasfu.ios.unity.native-plugin.capture")

    init(factory: RTCPeerConnectionFactory) {
        self.factory = factory
    }

    func makeTrackResource(for trackKind: MediaSFUUnityTrackKind) throws -> MediaSFUUnityLocalTrackResource {
        switch trackKind {
        case .audio:
            let trackId = "mediasfu_unity_audio_\(UUID().uuidString)"
            let audioSource = factory.audioSource(with: nil)
            let audioTrack = factory.audioTrack(with: audioSource, trackId: trackId)
            return MediaSFUUnityLocalTrackResource(track: audioTrack) {
                _ = audioSource
            }

        case .video:
            return try makeCameraTrackResource()

        case .screen:
#if os(macOS)
            return try makeScreenTrackResource()
#else
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin does not yet support screen-share capture through the standalone bridge."
            )
#endif

        case .whiteboard:
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin does not yet support whiteboard track production."
            )
        }
    }

    private func makeCameraTrackResource() throws -> MediaSFUUnityLocalTrackResource {
        let videoSource = factory.videoSource()
        videoSource.adaptOutputFormat(
            toWidth: Int32(Self.cameraWidth),
            height: Int32(Self.cameraHeight),
            fps: Int32(Self.cameraFrameRate)
        )
        let trackId = "mediasfu_unity_video_\(UUID().uuidString)"
        let videoTrack = factory.videoTrack(with: videoSource, trackId: trackId)

        guard let device = RTCCameraVideoCapturer.captureDevices().first else {
#if os(macOS)
            if Self.shouldUseSyntheticVideoFallback() {
                return makeSyntheticCameraTrackResource(videoTrack: videoTrack, videoSource: videoSource)
            }
#endif
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin could not resolve a camera device for video production."
            )
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.first else {
#if os(macOS)
            if Self.shouldUseSyntheticVideoFallback() {
                return makeSyntheticCameraTrackResource(videoTrack: videoTrack, videoSource: videoSource)
            }
#endif
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin could not resolve a capture format for the selected camera device."
            )
        }

        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        let semaphore = DispatchSemaphore(value: 0)
        var captureError: Error?
        var started = false

        captureQueue.async {
            capturer.startCapture(with: device, format: format, fps: Self.cameraFrameRate) { error in
                captureError = error
                started = true
                semaphore.signal()
            }
        }

        if semaphore.wait(timeout: .now() + 5) == .timedOut || !started {
#if os(macOS)
            if Self.shouldUseSyntheticVideoFallback() {
                return makeSyntheticCameraTrackResource(videoTrack: videoTrack, videoSource: videoSource)
            }
#endif
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin timed out while starting the camera capturer."
            )
        }

        if let captureError {
#if os(macOS)
            if Self.shouldUseSyntheticVideoFallback() {
                return makeSyntheticCameraTrackResource(videoTrack: videoTrack, videoSource: videoSource)
            }
#endif
            throw MediaSFUUnityNativePluginError(
                "MediaSFU Unity native plugin failed to start the camera capturer: \(captureError.localizedDescription)"
            )
        }

        return MediaSFUUnityLocalTrackResource(track: videoTrack) {
            let stopSemaphore = DispatchSemaphore(value: 0)
            self.captureQueue.async {
                capturer.stopCapture {
                    stopSemaphore.signal()
                }
            }
            _ = stopSemaphore.wait(timeout: .now() + 2)
        }
    }

#if os(macOS)
    private func makeSyntheticCameraTrackResource(
        videoTrack: RTCVideoTrack,
        videoSource: RTCVideoSource
    ) -> MediaSFUUnityLocalTrackResource {
        let capturer = MediaSFUIosUnitySyntheticVideoCapturer(
            videoSource: videoSource,
            targetWidth: Self.cameraWidth,
            targetHeight: Self.cameraHeight,
            frameRate: Self.syntheticCameraFrameRate
        )
        capturer.start()

        return MediaSFUUnityLocalTrackResource(track: videoTrack) {
            capturer.stop()
        }
    }

    private static func shouldUseSyntheticVideoFallback() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["MEDIASFU_UNITY_ENABLE_SYNTHETIC_VIDEO"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if explicit == "1" || explicit == "true" || explicit == "yes" {
                return true
            }
            if explicit == "0" || explicit == "false" || explicit == "no" {
                return false
            }
        }

        let arguments = Set(ProcessInfo.processInfo.arguments)
        return arguments.contains("-batchmode") || arguments.contains("-nographics")
    }

    private func makeScreenTrackResource() throws -> MediaSFUUnityLocalTrackResource {
        let displayId = CGMainDisplayID()
        let captureSize = Self.resolveScreenCaptureSize(for: displayId)
        let videoSource = factory.videoSource()
        videoSource.adaptOutputFormat(
            toWidth: Int32(captureSize.width),
            height: Int32(captureSize.height),
            fps: Int32(Self.screenFrameRate)
        )

        let trackId = "mediasfu_unity_screen_\(UUID().uuidString)"
        let videoTrack = factory.videoTrack(with: videoSource, trackId: trackId)
        let capturer = MediaSFUIosUnityMacOSDisplayCapturer(
            videoSource: videoSource,
            displayId: displayId,
            targetWidth: captureSize.width,
            targetHeight: captureSize.height,
            frameRate: Self.screenFrameRate
        )

        try capturer.start()

        return MediaSFUUnityLocalTrackResource(track: videoTrack) {
            capturer.stop()
        }
    }

    private static func resolveScreenCaptureSize(for displayId: CGDirectDisplayID) -> (width: Int, height: Int) {
        let nativeWidth = Int(CGDisplayPixelsWide(displayId))
        let nativeHeight = Int(CGDisplayPixelsHigh(displayId))
        guard nativeWidth > 0, nativeHeight > 0 else {
            return (screenMaxWidth, screenMaxHeight)
        }

        let widthScale = Double(screenMaxWidth) / Double(nativeWidth)
        let heightScale = Double(screenMaxHeight) / Double(nativeHeight)
        let scale = min(1.0, widthScale, heightScale)

        let scaledWidth = Int((Double(nativeWidth) * scale).rounded(.down))
        let scaledHeight = Int((Double(nativeHeight) * scale).rounded(.down))

        return (
            width: makeEvenDimension(scaledWidth),
            height: makeEvenDimension(scaledHeight)
        )
    }

    private static func makeEvenDimension(_ value: Int) -> Int {
        let adjusted = max(16, value)
        return adjusted.isMultiple(of: 2) ? adjusted : adjusted - 1
    }
#endif
}
#else
final class MediaSFUIosUnityDefaultLocalTrackFactory {
    static let shared = MediaSFUIosUnityDefaultLocalTrackFactory()

    func makeTrackResource(for trackKind: MediaSFUUnityTrackKind) throws -> MediaSFUUnityLocalTrackResource {
        throw MediaSFUUnityNativePluginError(
            "MediaSFU Unity native plugin cannot create a \(trackKind.mediaTag) track because WebRTC is unavailable in this build."
        )
    }
}
#endif

@_cdecl("MediaSfuUnityCreateWebRtcEngine")
public func MediaSfuUnityCreateWebRtcEngine(_ payloadJson: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    let createPayloadJson = payloadJson.map { String(cString: $0) } ?? ""

    do {
        let engine = try MediaSFUIosUnityNativePluginFactory.makeEngine(createPayloadJson: createPayloadJson)
        return Unmanaged.passRetained(engine).toOpaque()
    } catch {
        fputs("MediaSFU Unity native plugin failed to create engine: \(error.localizedDescription)\n", stderr)
        return nil
    }
}

@_cdecl("MediaSfuUnityDestroyWebRtcEngine")
public func MediaSfuUnityDestroyWebRtcEngine(_ engineHandle: UnsafeMutableRawPointer?) {
    guard let engineHandle else {
        return
    }

    Unmanaged<MediaSFUIosUnityNativePluginEngine>.fromOpaque(engineHandle).release()
}

@_cdecl("MediaSfuUnityInvokeWebRtcEngine")
public func MediaSfuUnityInvokeWebRtcEngine(
    _ engineHandle: UnsafeMutableRawPointer?,
    _ operationName: UnsafePointer<CChar>?,
    _ payloadJson: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let engineHandle else {
        return duplicateCString(
            "{\"success\":false,\"error\":\"native_bridge_invalid_engine\",\"detail\":\"MediaSFU Unity native plugin received a null engine handle. Create the engine before invoking WebRTC operations.\",\"result\":null}"
        )
    }

    let engine = Unmanaged<MediaSFUIosUnityNativePluginEngine>.fromOpaque(engineHandle).takeUnretainedValue()
    let operation = operationName.map { String(cString: $0) } ?? ""
    let payload = payloadJson.map { String(cString: $0) } ?? ""
    return duplicateCString(engine.host.invoke(operationName: operation, payloadJson: payload))
}

@_cdecl("MediaSfuUnityCopyRemoteVideoFrame")
public func MediaSfuUnityCopyRemoteVideoFrame(
    _ engineHandle: UnsafeMutableRawPointer?,
    _ remoteProducerId: UnsafePointer<CChar>?,
    _ destination: UnsafeMutableRawPointer?,
    _ capacity: Int32
) -> Int32 {
    guard let engineHandle else {
        return 0
    }

    let engine = Unmanaged<MediaSFUIosUnityNativePluginEngine>.fromOpaque(engineHandle).takeUnretainedValue()
    let producerId = remoteProducerId.map { String(cString: $0) } ?? ""
    guard !producerId.isEmpty else {
        return 0
    }

    let copiedByteCount = engine.host.copyRemoteVideoFrame(
        remoteProducerId: producerId,
        destination: destination,
        capacity: Int(capacity)
    )
    return Int32(copiedByteCount)
}

@_cdecl("MediaSfuUnityFreeString")
public func MediaSfuUnityFreeString(_ responsePointer: UnsafeMutablePointer<CChar>?) {
    guard let responsePointer else {
        return
    }

    free(responsePointer)
}

private func duplicateCString(_ value: String) -> UnsafeMutablePointer<CChar>? {
    strdup(value)
}

private extension String {
    func takeUnlessBlank() -> String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
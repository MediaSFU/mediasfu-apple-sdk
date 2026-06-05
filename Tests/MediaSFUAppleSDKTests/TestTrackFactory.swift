import Foundation
@testable import MediaSFUAppleSDK

#if MEDIA_SFU_HAS_MEDIASOUP_CLIENT && canImport(WebRTC)
import WebRTC

private enum TestNativeTrackFactory {
    static let factory = RTCPeerConnectionFactory()
    static let lock = NSLock()
    static var retainedAudioSources: [RTCAudioSource] = []

    static func makeTrack() -> MediaSFUNativeTrack {
        let source = factory.audioSource(with: nil)
        let track = factory.audioTrack(with: source, trackId: "test-audio-\(UUID().uuidString)")

        lock.lock()
        retainedAudioSources.append(source)
        lock.unlock()

        return track
    }
}

func FakeTrack() -> MediaSFUNativeTrack {
    TestNativeTrackFactory.makeTrack()
}
#else
private final class TestFakeTrack: MediaSFUNativeTrack {}

func FakeTrack() -> MediaSFUNativeTrack {
    TestFakeTrack()
}
#endif

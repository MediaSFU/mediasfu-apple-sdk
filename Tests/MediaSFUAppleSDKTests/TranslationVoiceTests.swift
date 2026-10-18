import XCTest
@testable import MediaSFUAppleSDK

#if MEDIA_SFU_HAS_TRANSLATION_VOICES
#if canImport(MediaSFUSDK)
import MediaSFUSDK
#elseif canImport(shared)
import shared
#else
#error("Translation acceptance tests require the new KMP framework")
#endif

@MainActor
final class TranslationVoiceTests: XCTestCase {
    private func reply(_ changes: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = [
            "schemaVersion": 1, "provider": "test-provider", "language": "fr", "status": "available",
            "model": "test-model", "truncated": true,
            "voices": ["male": ["fixture-m"], "neutral": [["id": "fixture-n", "name": "Neutral", "gender": "neutral"]]]
        ]
        value.merge(changes) { _, new in new }
        return value
    }

    private func parse(_ value: Any?, language: String = "fr") -> MediaSFUTranslationCatalogue {
        MediaSFUTranslationCatalogue(TranslationVoiceCatalogueKt.parseTranslationVoiceCatalogue(response: value, language: language))
    }

    func testFrameworkIsLinkedAndStructuredLegacyNeutralMetadataSurviveSwiftExport() {
        XCTAssertTrue(MediaSFUKmpBridgeInstaller.isKmpModuleAvailable())
        let value = parse(reply())
        XCTAssertEqual(value.voices.map(\.id), ["fixture-m", "fixture-n"])
        XCTAssertEqual(value.voices.last?.gender, "neutral")
        XCTAssertEqual(value.provider, "test-provider")
        XCTAssertEqual(value.model, "test-model")
        XCTAssertEqual(value.schemaVersion, 1)
        XCTAssertTrue(value.truncated)
        XCTAssertTrue(value.voices.allSatisfy { $0.provider == "test-provider" && $0.language == "fr" })
    }

    func testMalformedEmptyUnavailableUnsupportedAndLanguageMismatchFailClosed() {
        for invalid in [nil, "malformed", false, [:], reply(["provider": ""]), reply(["schemaVersion": 2]),
                        reply(["language": "de"]), reply(["status": "unavailable"]),
                        reply(["error": ["code": "unavailable"]]), reply(["voices": []])] as [Any?] {
            let value = parse(invalid)
            XCTAssertTrue(value.voices.isEmpty())
            XCTAssertEqual(value.status, "unavailable")
        }
        let empty = parse(reply(["status": "empty"]))
        XCTAssertEqual(empty.status, "empty")
        XCTAssertTrue(empty.voices.isEmpty())
    }

    func testExactVoiceAndProviderAreAppliedWithoutInventingAnID() {
        let session = VoiceSessionStub()
        let model = MediaSFUTranslationVoicePickerModel(session: session)
        model.load(language: "fr")
        session.complete(parse(reply()))
        model.select("unknown")
        XCTAssertFalse(model.canApply)
        model.select("fixture-n")
        XCTAssertTrue(model.apply())
        XCTAssertEqual(session.applied, ["voiceId": "fixture-n", "ttsProvider": "test-provider"])
        XCTAssertFalse(model.canApply)
    }

    func testEveryContextChangeInvalidatesSelectionAndRejectsStaleReplies() {
        // Tokens reflect room, socket identity/reconnect, output language, provider/model, settings and mode.
        for change in ["room", "socket", "language", "provider", "model", "mode"] {
            let session = VoiceSessionStub()
            let model = MediaSFUTranslationVoicePickerModel(session: session)
            model.load(language: "fr")
            let stale = session.completions[0]
            session.complete(parse(reply()))
            model.select("fixture-n")
            session.revision = change
            XCTAssertFalse(model.canApply)
            model.refreshContext()
            XCTAssertNil(model.selectedID)
            XCTAssertTrue(model.loading)
            stale(parse(reply()))
            XCTAssertTrue(model.loading)
            XCTAssertFalse(model.canApply)
            session.complete(parse(reply(["provider": "replacement"])))
            XCTAssertNil(model.selectedID)
        }
    }

    func testCancellationModeSwitchAndLanguageChangeIgnoreLateReplies() {
        let session = VoiceSessionStub()
        let model = MediaSFUTranslationVoicePickerModel(session: session)
        model.load(language: "fr")
        let old = session.completions[0]
        model.load(language: "en")
        old(parse(reply()))
        XCTAssertTrue(model.loading)
        session.complete(parse(reply())) // Wrong language cannot authorize a selection.
        XCTAssertTrue(model.catalogue.voices.isEmpty())
        model.load(language: "fr", mode: "configured")
        XCTAssertFalse(model.loading)
        XCTAssertNil(model.selectedID)
        XCTAssertGreaterThanOrEqual(session.cancellations, 2)
        model.cancel()
        old(parse(reply()))
        XCTAssertTrue(model.catalogue.voices.isEmpty())
    }

    func testTimeoutCancelsTransportAndLateResponseCannotRestoreVoices() async throws {
        let session = VoiceSessionStub()
        let model = MediaSFUTranslationVoicePickerModel(session: session, timeout: 0.02)
        model.load(language: "fr")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.loading)
        XCTAssertEqual(session.cancellations, 1)
        session.complete(parse(reply()))
        XCTAssertTrue(model.catalogue.voices.isEmpty())
        XCTAssertFalse(model.canApply)
    }

    func testTransportMayRotateTokenWhenStartingANewRequest() {
        let session = VoiceSessionStub()
        session.rotateOnLoad = true
        let model = MediaSFUTranslationVoicePickerModel(session: session)
        model.load(language: "fr")
        session.complete(parse(reply()))
        model.select("fixture-n")
        XCTAssertTrue(model.apply())
    }

    func testNativeBridgeReturnsSafeUnavailableWithoutMountedRoom() async {
        let host = MediaSFUIosHostBridge()
        let session = MediaSFUKmpTranslationVoiceSession(host: host)
        let done = expectation(description: "bounded unavailable catalogue")
        let cancel = session.load(language: "fr", mode: "stock") { result in
            XCTAssertTrue(result.voices.isEmpty())
            XCTAssertEqual(result.status, "unavailable")
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)
        cancel()
        XCTAssertFalse(session.apply(language: "fr", mode: "stock", token: "old", voiceId: "fixture-n", provider: "test-provider"))
    }
}

@MainActor
private final class VoiceSessionStub: MediaSFUTranslationVoiceSession {
    var revision = "initial"
    var rotateOnLoad = false
    var completions: [(MediaSFUTranslationCatalogue) -> Void] = []
    var cancellations = 0
    var applied: [String: String] = [:]
    func contextToken(language: String, mode: String) -> String { "\(revision)/\(language)/\(mode)" }
    func load(language: String, mode: String, completion: @escaping (MediaSFUTranslationCatalogue) -> Void) -> () -> Void {
        if rotateOnLoad { revision = UUID().uuidString }
        completions.append(completion)
        return { self.cancellations += 1 }
    }
    func complete(_ value: MediaSFUTranslationCatalogue) { completions.last?(value) }
    func apply(language: String, mode: String, token: String, voiceId: String, provider: String) -> Bool {
        guard token == contextToken(language: language, mode: mode) else { return false }
        applied = ["voiceId": voiceId, "ttsProvider": provider]
        return true
    }
}
#endif

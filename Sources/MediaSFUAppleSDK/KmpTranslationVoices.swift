#if MEDIA_SFU_HAS_TRANSLATION_VOICES && (canImport(MediaSFUSDK) || canImport(shared))
#if canImport(MediaSFUSDK)
import MediaSFUSDK
#else
import shared
#endif

extension MediaSFUTranslationCatalogue {
    init(_ source: TranslationVoiceCatalogue) {
        self.init(provider: source.provider, language: source.language,
                  voices: source.voices.map {
                      MediaSFUTranslationVoice(id: $0.id, name: $0.name, gender: $0.gender,
                                               provider: $0.provider, language: $0.language)
                  }, status: source.status, model: source.model,
                  schemaVersion: Int(source.schemaVersion), truncated: source.truncated)
    }
}

@MainActor
public final class MediaSFUKmpTranslationVoiceSession: MediaSFUTranslationVoiceSession {
    private let host: MediaSFUIosHostBridge
    public init(host: MediaSFUIosHostBridge) { self.host = host }
    public func contextToken(language: String, mode: String) -> String {
        host.translationVoices.contextToken(language: language, mode: mode)
    }
    public func load(language: String, mode: String,
                     completion: @escaping (MediaSFUTranslationCatalogue) -> Void) -> () -> Void {
        let request = host.translationVoices.load(language: language, mode: mode) {
            completion(MediaSFUTranslationCatalogue($0))
        }
        return { request.cancel() }
    }
    public func apply(language: String, mode: String, token: String, voiceId: String, provider: String) -> Bool {
        host.translationVoices.apply(language: language, mode: mode, token: token, voiceId: voiceId, provider: provider)
    }
}
#endif

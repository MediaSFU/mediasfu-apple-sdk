import Foundation
import Combine

public struct MediaSFUTranslationVoice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let gender: String
    public let provider: String
    public let language: String

    public init(id: String, name: String, gender: String, provider: String, language: String) {
        self.id = id; self.name = name; self.gender = gender
        self.provider = provider; self.language = language
    }
}

public struct MediaSFUTranslationCatalogue: Equatable {
    public let provider: String
    public let language: String
    public let voices: [MediaSFUTranslationVoice]
    public let status: String
    public let model: String?
    public let schemaVersion: Int
    public let truncated: Bool

    public init(provider: String, language: String, voices: [MediaSFUTranslationVoice], status: String,
                model: String? = nil, schemaVersion: Int = 1, truncated: Bool = false) {
        self.provider = provider; self.language = language; self.voices = voices
        self.status = status; self.model = model; self.schemaVersion = schemaVersion; self.truncated = truncated
    }

    static func unavailable(_ language: String) -> Self {
        Self(provider: "", language: language, voices: [], status: "unavailable", model: nil,
             schemaVersion: 1, truncated: false)
    }
}

/// Main-thread transport for the room that owns the picker. Tokens are opaque and contain no credentials.
@MainActor
public protocol MediaSFUTranslationVoiceSession: AnyObject {
    func contextToken(language: String, mode: String) -> String
    func load(language: String, mode: String,
              completion: @escaping (MediaSFUTranslationCatalogue) -> Void) -> () -> Void
    func apply(language: String, mode: String, token: String, voiceId: String, provider: String) -> Bool
}

/// Selection is valid only for one completed request in one room/configuration/language/mode context.
@MainActor
public final class MediaSFUTranslationVoicePickerModel: ObservableObject {
    @Published public private(set) var catalogue: MediaSFUTranslationCatalogue = .unavailable("")
    @Published public private(set) var selectedID: String?
    @Published public private(set) var loading = false
    @Published public private(set) var submitted = false
    private let session: MediaSFUTranslationVoiceSession
    private let timeout: TimeInterval
    private var cancelRequest: (() -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var generation = UUID()
    private var token = ""
    private var language = ""
    private var mode = "configured"

    public init(session: MediaSFUTranslationVoiceSession, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = min(max(timeout, 0.01), 20)
    }

    public func cancel() {
        generation = UUID()
        timeoutWork?.cancel()
        timeoutWork = nil
        cancelRequest?()
        cancelRequest = nil
        selectedID = nil
        loading = false
        submitted = false
        catalogue = .unavailable(language)
        token = session.contextToken(language: language, mode: mode)
    }

    public func load(language: String, mode: String = "stock") {
        cancel()
        self.language = language
        self.mode = mode
        token = session.contextToken(language: language, mode: mode)
        catalogue = .unavailable(language)
        guard mode == "stock", !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true
        let requestGeneration = generation
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.generation == requestGeneration, self.loading else { return }
            self.cancel()
        }
        timeoutWork = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: expiry)
        let cancellation = session.load(language: language, mode: mode) { [weak self] value in
            guard let self, self.generation == requestGeneration, self.loading else { return }
            guard self.contextIsCurrent else { self.cancel(); return }
            self.timeoutWork?.cancel()
            self.timeoutWork = nil
            self.loading = false
            if value.language.caseInsensitiveCompare(language) == .orderedSame,
               value.schemaVersion == 1, ["available", "empty"].contains(value.status),
               !value.provider.isEmpty {
                self.catalogue = value
            } else {
                self.catalogue = .unavailable(language)
            }
        }
        if generation == requestGeneration {
            cancelRequest = cancellation
            token = session.contextToken(language: language, mode: mode)
        } else {
            cancellation()
        }
    }

    private var contextIsCurrent: Bool {
        session.contextToken(language: language, mode: mode) == token
    }

    /// Call while the picker is visible. Apply also checks synchronously, so polling is only for UI freshness.
    public func refreshContext() {
        if !contextIsCurrent { load(language: language, mode: mode) }
    }

    public func select(_ id: String?) {
        guard contextIsCurrent else { cancel(); return }
        selectedID = id.flatMap { candidate in
            !loading && catalogue.status == "available" && catalogue.voices.contains {
                $0.id == candidate && $0.provider == catalogue.provider && $0.language == catalogue.language
            } ? candidate : nil
        }
    }

    public var canApply: Bool {
        !loading && mode == "stock" && contextIsCurrent && selectedID != nil && catalogue.status == "available"
    }

    @discardableResult public func apply() -> Bool {
        guard canApply, let selectedID else { cancel(); return false }
        let accepted = session.apply(language: language, mode: mode, token: token,
                                     voiceId: selectedID, provider: catalogue.provider)
        cancel()
        submitted = accepted
        token = session.contextToken(language: language, mode: mode)
        return accepted
    }
}

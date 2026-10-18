import Foundation
import CoreFoundation
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

    /// Parses Foundation replies for custom native transports. KMP sessions already return typed catalogues.
    public static func parse(_ response: Any?, language: String) -> Self {
        guard let data = response as? [String: Any],
              let groups = data["voices"] as? [String: Any],
              let rawProvider = data["provider"] as? String else { return .unavailable(language) }
        let provider = rawProvider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !provider.isEmpty else { return .unavailable(language) }
        if let schema = data["schemaVersion"] {
            guard let number = schema as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == 1 else { return .unavailable(language) }
        }
        let resultLanguage = data["language"] as? String ?? language
        guard resultLanguage.caseInsensitiveCompare(language) == .orderedSame else { return .unavailable(language) }
        if let error = data["error"], !(error is NSNull) {
            let falseBoolean = (error as? NSNumber).map {
                CFGetTypeID($0) == CFBooleanGetTypeID() && !$0.boolValue
            } ?? false
            guard falseBoolean || (error as? String) == "" else { return .unavailable(language) }
        }
        let status = data["status"] as? String
        guard status == nil || status == "available" || status == "empty" else { return .unavailable(language) }
        let genders = ["male", "female", "neutral"]
        var seen = Set<String>()
        var voices: [MediaSFUTranslationVoice] = []
        for group in genders {
            for entry in groups[group] as? [Any] ?? [] {
                let fields = entry as? [String: Any]
                guard let id = (entry as? String) ?? (fields?["id"] as? String),
                      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if let declared = fields?["provider"] as? String,
                   declared.caseInsensitiveCompare(provider) != .orderedSame { continue }
                guard seen.insert(id).inserted else { continue }
                let suppliedGender = fields?["gender"] as? String
                let gender = suppliedGender.map { genders.contains($0) ? $0 : "neutral" } ?? group
                let name = (fields?["name"] as? String).flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                } ?? id
                voices.append(.init(id: id, name: name, gender: gender, provider: provider, language: resultLanguage))
            }
        }
        let truncated = (data["truncated"] as? NSNumber).map {
            CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue
        } ?? false
        return Self(provider: provider, language: resultLanguage,
                    voices: status == "empty" ? [] : voices,
                    status: status == "empty" || voices.isEmpty ? "empty" : "available",
                    model: data["model"] as? String, truncated: truncated)
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
    @Published public private(set) var applicationFailed = false
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
        applicationFailed = false
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
        guard canApply, let selectedID else { cancel(); applicationFailed = true; return false }
        let accepted = session.apply(language: language, mode: mode, token: token,
                                     voiceId: selectedID, provider: catalogue.provider)
        cancel()
        submitted = accepted
        applicationFailed = !accepted
        token = session.contextToken(language: language, mode: mode)
        return accepted
    }
}

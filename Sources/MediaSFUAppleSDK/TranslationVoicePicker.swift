#if canImport(SwiftUI)
import SwiftUI

/// An additive stock-voice picker. Enable spoken translation in the hosted room before applying.
@MainActor
public struct MediaSFUTranslationVoicePicker: View {
    @StateObject private var model: MediaSFUTranslationVoicePickerModel
    @State private var language: String
    @State private var mode = "stock"
    private let clock = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public init(session: MediaSFUTranslationVoiceSession, outputLanguage: String) {
        _model = StateObject(wrappedValue: MediaSFUTranslationVoicePickerModel(session: session))
        _language = State(initialValue: outputLanguage)
    }

    public var body: some View {
        Form {
            Section(header: Text("Translation voice")) {
                Text("Enable spoken translation in the room settings first. Choose an output language supported by your room.")
                TextField("Output language code", text: $language)
                    .disableAutocorrection(true)
                Picker("Voice mode", selection: $mode) {
                    Text("Stock voice").tag("stock")
                    Text("Configured voice").tag("configured")
                }
            }
            if mode == "stock" {
                Section(header: Text("Stock voices")) {
                    if model.loading {
                        ProgressView("Loading voices…")
                    } else if model.catalogue.voices.isEmpty {
                        Text(model.catalogue.status == "empty" ? "No stock voices for this language." : "Voice catalogue unavailable.")
                        Button("Retry") { reload() }
                    } else {
                        Text([model.catalogue.provider, model.catalogue.model].compactMap { $0 }.joined(separator: " · "))
                        ForEach(model.catalogue.voices) { voice in
                            Button { model.select(voice.id) } label: {
                                HStack {
                                    Text("\(voice.name) · \(voice.gender)")
                                    Spacer()
                                    if model.selectedID == voice.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        if model.catalogue.truncated { Text("The provider returned a limited voice list.") }
                    }
                    Button("Apply voice") { model.apply() }.disabled(!model.canApply)
                    if model.submitted { Text("Voice settings submitted. The server validates the selection.") }
                }
            } else {
                Text("Use the hosted translation settings to apply a basic preference or your existing clone configuration.")
            }
        }
        .navigationTitle("Translation voice")
        .onAppear { reload() }
        .onChange(of: language) { _ in reload() }
        .onChange(of: mode) { _ in reload() }
        .onReceive(clock) { _ in model.refreshContext() }
        .onDisappear { model.cancel() }
    }

    private func reload() { model.load(language: language, mode: mode) }
}
#endif

import ShellXAppCore
import SwiftUI

/// Settings › Voice: the spoken language, and where the voice is recognised for it (spec section 4):
/// on this iPhone, on Apple's servers (said plainly, with ShellX never receiving the voice), or not
/// at all right now (typing still works).
struct VoiceSection: View {
    let service: VoiceService

    var body: some View {
        Section {
            Picker(
                selection: Binding(get: { service.language }, set: { service.setLanguage($0) })
            ) {
                ForEach(VoiceLanguage.allCases, id: \.self) { language in
                    Text(Self.name(language)).tag(language)
                }
            } label: {
                Text(LocalizedStringResource("settings.voice.language"))
            }
            .accessibilityIdentifier("settings.voice.language")
        } header: {
            Text(LocalizedStringResource("settings.voice.title"))
        } footer: {
            if service.engineKnown {
                Text(verbatim: Self.explanation(service.engine, language: service.language))
                    .accessibilityIdentifier("settings.voice.engine")
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: service.language) { await service.refreshEngine() }
    }

    static func name(_ language: VoiceLanguage) -> LocalizedStringResource {
        switch language {
        case .vietnamese: return LocalizedStringResource("voice.language.vietnamese")
        case .english: return LocalizedStringResource("voice.language.english")
        }
    }

    /// The line under the picker for `engine`.
    static func explanation(_ engine: VoiceEngine?, language: VoiceLanguage) -> String {
        switch engine {
        case .analyzer, .onDevice:
            return String(localized: "settings.voice.onDevice")
        case .server:
            return String(localized: "settings.voice.server \(String(localized: name(language)))")
        case nil:
            return String(localized: "settings.voice.unavailable")
        }
    }
}

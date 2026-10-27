import ShellXAppCore
import SwiftUI

/// The bar at the bottom of a conversation: an optional row above (the home's "Send to:" chip),
/// then the mic, or the text field with its send button.
///
/// With a `VoiceService` in the environment the mic comes first (spec section 4): hold to talk,
/// release to send (through `sendVoice`), swipe up or the keyboard button to type. The words show
/// above the bar while the user talks. The field shows while it is being typed in or holds text,
/// and the keyboard opens by itself when no recognizer can run. Without a `VoiceService`, only the
/// field shows.
///
/// The text is checked as it changes (`ComposerValidation`): past 16 384 bytes the bar says "Too
/// long" and the button stays off, so nothing that long ever leaves the phone. A dictation stops at
/// that limit by itself; its words then go into the field to be read before sending.
struct ComposerBar<Accessory: View>: View {
    @Binding var text: String
    let send: (String) -> Void
    /// Sends what was said (the home marks it as said by voice); nil uses `send`.
    let sendVoice: ((String) -> Void)?
    let accessory: Accessory
    /// The dictation for render tests; otherwise one is made from the environment's `VoiceService`.
    private let injectedVoice: VoiceInputModel?

    @Environment(VoiceService.self) private var voiceService: VoiceService?
    @State private var ownVoice: VoiceInputModel?
    /// The user asked for the keyboard (button, swipe up, or no recognizer).
    @State private var typing = false
    /// A dictation cut at the limit, put in the field: the limit line shows while the field holds it.
    @State private var cutText: String?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    init(
        text: Binding<String>, send: @escaping (String) -> Void, sendVoice: ((String) -> Void)? = nil,
        voice: VoiceInputModel? = nil, @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        self.send = send
        self.sendVoice = sendVoice
        injectedVoice = voice
        self.accessory = accessory()
    }

    private var voice: VoiceInputModel? { injectedVoice ?? ownVoice }
    private var showsField: Bool { voice == nil || typing || focused || !text.isEmpty }

    var body: some View {
        let validation = ComposerValidation(text)
        VStack(alignment: .leading, spacing: 4) {
            accessory
            if let voice {
                VoiceStatusView(model: voice, level: voiceService?.meter.level ?? 0)
                    .padding(.bottom, 2)
            }
            if showsField {
                field(validation)
            } else if let voice {
                micRow(voice)
            }
            if case let .tooLong(bytes) = validation {
                let used = ComposerValidation.byteCount(bytes)
                let limit = ComposerValidation.byteCount(ComposerValidation.maxBytes)
                Text(verbatim: String(localized: "composer.tooLong \(used) \(limit)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("composer.tooLong")
            } else if let cutText, cutText == text {
                let limit = ComposerValidation.byteCount(ComposerValidation.maxBytes)
                Text(verbatim: String(localized: "voice.limit \(limit)"))
                    .font(.caption)
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("composer.voiceLimit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onAppear {
            if injectedVoice == nil, ownVoice == nil { ownVoice = voiceService?.makeModel() }
        }
        // Another screen covers this one: the microphone never stays on behind it.
        .onDisappear {
            let voice = self.voice
            Task { await voice?.cancel() }
        }
        .onChange(of: voice?.wantsKeyboard ?? false, initial: true) { _, wants in
            guard wants else { return }
            voice?.wantsKeyboard = false
            openKeyboard()
        }
        .onChange(of: focused) { _, isFocused in
            // The keyboard went away with nothing typed: back to the mic.
            if !isFocused, text.isEmpty { typing = false }
        }
        .onChange(of: text) { _, newText in
            // Typing replaces a "can't listen" message.
            if !newText.isEmpty { voice?.dismiss() }
        }
    }

    private func field(_ validation: ComposerValidation) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String(localized: "composer.placeholder"), text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("composer.field")
            Button {
                guard case let .ok(message) = validation else { return }
                send(message)
                text = ""
                cutText = nil
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(PrimaryButtonStyle.label)
                    .frame(width: max(buttonSize, 44), height: max(buttonSize, 44))
                    .background(PrimaryButtonStyle.fill, in: Circle())
            }
            .disabled(!validation.canSend)
            .opacity(validation.canSend ? 1 : 0.4)
            .accessibilityLabel(Text(LocalizedStringResource("composer.send")))
            .accessibilityIdentifier("composer.send")
        }
    }

    /// The mic in the middle, the keyboard button at the trailing edge, the hint below.
    private func micRow(_ voice: VoiceInputModel) -> some View {
        VStack(spacing: 4) {
            MicButton(model: voice, label: LocalizedStringResource("voice.mic"), onOutcome: said, onKeyboard: openKeyboard)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button(action: openKeyboard) {
                        Image(systemName: "keyboard")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color("AccentText"))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text(LocalizedStringResource("voice.keyboard")))
                    .accessibilityIdentifier("composer.keyboard")
                }
            Text(LocalizedStringResource("voice.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .padding(.top, 2)
    }

    /// The keyboard button, "Type instead", a swipe up, or no recognizer: a dictation in progress is
    /// cancelled first (`VoiceInputModel.typeInstead()`), so nothing heard while typing is sent later.
    private func openKeyboard() {
        let voice = self.voice
        typing = true
        Task { @MainActor in
            await voice?.typeInstead()
            // The field appeared in the update before; focus it now.
            focused = true
        }
    }

    /// Released with words: whole ones are sent; words stopped at the limit go into the field, to be
    /// read before sending (`VoiceInputModel.outcome(for:)`).
    private func said(_ outcome: DictationOutcome) {
        switch outcome {
        case let .complete(words):
            (sendVoice ?? send)(words)
        case let .cutAtLimit(words):
            text = words
            cutText = words
            openKeyboard()
        }
    }
}

extension ComposerValidation {
    /// A byte count in the app's language: "16,384" in English, "16 384" in Vietnamese (a no-break
    /// space, where the locale's own grouping would give "16.384").
    static func byteCount(_ count: Int, locale: Locale = .app) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if locale.language.languageCode == .vietnamese { formatter.groupingSeparator = "\u{00A0}" }
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    /// Whether the send button acts.
    var canSend: Bool {
        if case .ok = self { return true }
        return false
    }
}

extension ComposerBar where Accessory == EmptyView {
    init(
        text: Binding<String>, send: @escaping (String) -> Void, sendVoice: ((String) -> Void)? = nil,
        voice: VoiceInputModel? = nil
    ) {
        self.init(text: text, send: send, sendVoice: sendVoice, voice: voice) { EmptyView() }
    }
}

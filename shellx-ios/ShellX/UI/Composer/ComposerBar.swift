import ShellXAppCore
import SwiftUI

/// The bar at the bottom of a conversation: an optional row above (the home's "Send to:" chip),
/// then the text field with one round button at its trailing edge, and a "+" at its leading edge
/// when the target's Mac takes attachments.
///
/// The field always shows: a tap on it brings the keyboard, with no gesture to learn. With a
/// `VoiceService` in the environment and the field empty, the button is the mic (spec section 4):
/// hold to talk, release to send (through `sendVoice`), drag left to cancel; the words show above
/// the bar while the user talks. Once the field holds text the button is Send. The keyboard opens by
/// itself when no recognizer can run, and then the mic steps aside. Without a `VoiceService`, the
/// button is always Send.
///
/// The text is checked as it changes (`ComposerValidation`): past 16 384 bytes the bar says "Too
/// long" and the button stays off, so nothing that long ever leaves the phone. A dictation stops at
/// that limit by itself; its words then go into the field to be read before sending.
///
/// `onBegin` and `onEnd` tell the home when a message starts (the mic pressed, the field focused)
/// and when it is dropped (released with nothing said, the keyboard closed with the field empty),
/// so it goes to the session the chip showed when it started.
///
/// With `attachments`, the "+" adds photos and files (`AttachMenu`); they wait in a row above the
/// field (`AttachmentStrip`) and make the button Send even with no text. Too many, or one too big,
/// is said in red under the field like "Too long", and the button stays off. A message with
/// attachments stays in the bar while it is sent: `sending` (the upload's progress) locks the bar
/// and turns the button into a progress ring, and the owner clears the text and the attachments
/// once the Mac took them, or leaves them to send again. A message of text only leaves the field at
/// once, as before.
struct ComposerBar<Accessory: View>: View {
    @Binding var text: String
    /// The photos and files the message carries; nil when the target's Mac takes none (no "+").
    let attachments: Binding<[OutgoingAttachment]>?
    /// How far the attachments of the message being sent got; not nil locks the bar.
    let sending: Double?
    /// The trimmed text (empty with attachments only) and the attachments.
    let send: (String, [OutgoingAttachment]) -> Void
    /// Sends what was said (the home marks it as said by voice); nil uses `send`.
    let sendVoice: ((String) -> Void)?
    /// A message started: the mic was pressed, or the field got focus.
    let onBegin: (() -> Void)?
    /// The message was dropped: the mic released with nothing to send while the field is empty and
    /// unfocused, the keyboard closed with the field empty, or the bar went away empty.
    let onEnd: (() -> Void)?
    let accessory: Accessory
    /// The dictation for render tests; otherwise one is made from the environment's `VoiceService`.
    private let injectedVoice: VoiceInputModel?

    @Environment(VoiceService.self) private var voiceService: VoiceService?
    @State private var ownVoice: VoiceInputModel?
    /// A dictation cut at the limit, put in the field: the limit line shows while the field holds it.
    @State private var cutText: String?
    /// Why something picked was not added (too big, unreadable, too many).
    @State private var attachNote: String?
    /// Picks still being read: Send waits for them.
    @State private var loadingPicks = 0
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    init(
        text: Binding<String>, attachments: Binding<[OutgoingAttachment]>? = nil, sending: Double? = nil,
        send: @escaping (String, [OutgoingAttachment]) -> Void, sendVoice: ((String) -> Void)? = nil,
        onBegin: (() -> Void)? = nil, onEnd: (() -> Void)? = nil, voice: VoiceInputModel? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        self.attachments = attachments
        self.sending = sending
        self.send = send
        self.sendVoice = sendVoice
        self.onBegin = onBegin
        self.onEnd = onEnd
        injectedVoice = voice
        self.accessory = accessory()
    }

    private var voice: VoiceInputModel? { injectedVoice ?? ownVoice }

    private var picked: [OutgoingAttachment] { attachments?.wrappedValue ?? [] }

    /// The mic, while the field and the attachments are empty, nothing is being picked or sent, and
    /// a recognizer can run.
    private var mic: VoiceInputModel? {
        guard let voice, text.isEmpty, picked.isEmpty, loadingPicks == 0, sending == nil else { return nil }
        if case .unavailable = voice.phase { return nil }
        return voice
    }

    var body: some View {
        let validation = ComposerValidation.message(text, attachments: picked)
        VStack(alignment: .leading, spacing: 4) {
            accessory
            if let voice {
                VoiceStatusView(model: voice, level: voiceService?.meter.level ?? 0)
                    .padding(.bottom, 2)
            }
            if let attachments, !attachments.wrappedValue.isEmpty || loadingPicks > 0 {
                AttachmentStrip(
                    attachments: attachments, locked: sending != nil, loading: loadingPicks,
                    removed: { attachNote = nil })
                    .padding(.bottom, 2)
            }
            field(validation)
            if case let .tooLong(bytes) = validation {
                let used = ComposerValidation.byteCount(bytes)
                let limit = ComposerValidation.byteCount(ComposerValidation.maxBytes)
                Text(verbatim: String(localized: "composer.tooLong \(used) \(limit)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("composer.tooLong")
            } else if let problem = Self.problem(validation) ?? attachNote {
                Text(verbatim: problem)
                    .font(.caption)
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("composer.attachProblem")
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
        .background(Color.appBackground)
        .overlay(alignment: .top) { Divider() }
        .onAppear {
            if injectedVoice == nil, ownVoice == nil { ownVoice = voiceService?.makeModel() }
        }
        // Another screen covers this one: the microphone never stays on behind it, and a message
        // that holds no text is over.
        .onDisappear {
            let voice = self.voice
            Task { await voice?.cancel() }
            if text.isEmpty { onEnd?() }
        }
        .onChange(of: voice?.wantsKeyboard ?? false, initial: true) { _, wants in
            guard wants else { return }
            voice?.wantsKeyboard = false
            openKeyboard()
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                onBegin?()
            } else if text.isEmpty {
                // The keyboard went away with nothing typed: no message.
                onEnd?()
            }
        }
        .onChange(of: text) { _, newText in
            guard !newText.isEmpty, let voice else { return }
            // Typing replaces a "can't listen" message.
            voice.dismiss()
            // Text in the field hides the mic (a draft put back, for instance): a dictation still
            // listening is cancelled, so a hidden mic never keeps running.
            if voice.isActive { Task { await voice.typeInstead() } }
        }
    }

    private func field(_ validation: ComposerValidation) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if let attachments {
                AttachMenu(attachments: attachments, loading: $loadingPicks, side: side, note: { attachNote = $0 })
                    .disabled(sending != nil)
                    .opacity(sending != nil ? 0.4 : 1)
            }
            TextField(String(localized: "composer.placeholder"), text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .disabled(sending != nil)
                .foregroundStyle(sending != nil ? .secondary : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("composer.field")
            Group {
                if let mic {
                    MicButton(
                        model: mic, label: LocalizedStringResource("voice.mic"), diameter: side,
                        onOutcome: said, onKeyboard: openKeyboard, onPress: onBegin,
                        onNothing: {
                            // Swiping up to type keeps the message (and where it goes) for the keyboard.
                            if !focused, text.isEmpty { onEnd?() }
                        })
                } else {
                    sendButton(validation)
                }
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .animation(.snappy(duration: 0.2), value: mic == nil)
    }

    /// The round button's side: 44 points, grown with the text size.
    private var side: CGFloat { max(buttonSize, 44) }

    @ViewBuilder private func sendButton(_ validation: ComposerValidation) -> some View {
        if let sending {
            ProgressView(value: sending)
                .progressViewStyle(SendProgressStyle(side: side))
                .accessibilityLabel(Text(LocalizedStringResource("composer.sending")))
                .accessibilityIdentifier("composer.sending")
        } else {
            sendButtonIdle(validation)
        }
    }

    private func sendButtonIdle(_ validation: ComposerValidation) -> some View {
        let canSend = validation.canSend && loadingPicks == 0
        return Button {
            // A pick still being read would arrive after its message left.
            guard case let .ok(message) = validation, loadingPicks == 0 else { return }
            let carried = picked
            send(message, carried)
            attachNote = nil
            // With attachments the bar keeps the message while it goes up; the owner clears it.
            guard carried.isEmpty else { return }
            text = ""
            cutText = nil
        } label: {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(PrimaryButtonStyle.label)
                .frame(width: side, height: side)
                .background(PrimaryButtonStyle.fill, in: Circle())
        }
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.4)
        .accessibilityLabel(Text(LocalizedStringResource("composer.send")))
        .accessibilityIdentifier("composer.send")
    }

    /// "Type instead", a swipe up on the mic, or no recognizer: the keyboard comes up at once, and a
    /// dictation in progress is cancelled (`VoiceInputModel.typeInstead()`), so nothing heard while
    /// typing is sent later. The keyboard never waits for the recognizer to stop.
    private func openKeyboard() {
        focused = true
        let voice = self.voice
        Task { await voice?.typeInstead() }
    }

    /// Released with words: whole ones are sent; words stopped at the limit go into the field, to be
    /// read before sending (`VoiceInputModel.outcome(for:)`).
    private func said(_ outcome: DictationOutcome) {
        switch outcome {
        case let .complete(words):
            if let sendVoice { sendVoice(words) } else { send(words, []) }
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

extension ComposerBar {
    /// The red line for too many attachments or one too big; nil otherwise.
    static func problem(_ validation: ComposerValidation) -> String? {
        switch validation {
        case .tooManyAttachments: String(localized: "composer.attach.tooMany")
        case let .attachmentTooLarge(name): AttachmentPreparer.Failure.tooLarge(name: name).message
        case .empty, .ok, .tooLong: nil
        }
    }
}

/// The send button while a message's attachments go up: its arrow, dimmed, in a ring that fills
/// with the bytes sent.
private struct SendProgressStyle: ProgressViewStyle {
    let side: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        ZStack {
            Circle().fill(PrimaryButtonStyle.fill.opacity(0.16))
            Circle().inset(by: 2).stroke(PrimaryButtonStyle.fill.opacity(0.25), lineWidth: 3)
            Circle().inset(by: 2).trim(from: 0, to: fraction)
                .stroke(PrimaryButtonStyle.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(PrimaryButtonStyle.fill)
        }
        .frame(width: side, height: side)
        .animation(.linear(duration: 0.15), value: fraction)
    }
}

extension ComposerBar where Accessory == EmptyView {
    init(
        text: Binding<String>, attachments: Binding<[OutgoingAttachment]>? = nil, sending: Double? = nil,
        send: @escaping (String, [OutgoingAttachment]) -> Void, sendVoice: ((String) -> Void)? = nil,
        onBegin: (() -> Void)? = nil, onEnd: (() -> Void)? = nil, voice: VoiceInputModel? = nil
    ) {
        self.init(
            text: text, attachments: attachments, sending: sending, send: send, sendVoice: sendVoice,
            onBegin: onBegin, onEnd: onEnd, voice: voice
        ) {
            EmptyView()
        }
    }
}

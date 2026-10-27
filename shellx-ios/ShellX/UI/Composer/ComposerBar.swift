import ShellXAppCore
import SwiftUI

/// The bar at the bottom of a conversation: an optional row above the field (the home's "Send
/// to:" chip), a field of one to five lines, and the send button.
///
/// The text is checked as it changes (`ComposerValidation`): past 16 384 bytes the bar says "Too
/// long" and the button stays off, so nothing that long ever leaves the phone. Sending hands the
/// trimmed text to `send` and empties the field.
struct ComposerBar<Accessory: View>: View {
    @Binding var text: String
    let send: (String) -> Void
    let accessory: Accessory

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    init(text: Binding<String>, send: @escaping (String) -> Void, @ViewBuilder accessory: () -> Accessory) {
        _text = text
        self.send = send
        self.accessory = accessory()
    }

    var body: some View {
        let validation = ComposerValidation(text)
        VStack(alignment: .leading, spacing: 4) {
            accessory
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
            if case let .tooLong(bytes) = validation {
                let used = ComposerValidation.byteCount(bytes)
                let limit = ComposerValidation.byteCount(ComposerValidation.maxBytes)
                Text(verbatim: String(localized: "composer.tooLong \(used) \(limit)"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color("StatusError"))
                    .accessibilityIdentifier("composer.tooLong")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
    init(text: Binding<String>, send: @escaping (String) -> Void) {
        self.init(text: text, send: send) { EmptyView() }
    }
}

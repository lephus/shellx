import SwiftUI
import UIKit

/// The email field of the sign-in screen. It is a UIKit text field because only a UIKit responder can ask iOS for a
/// keyboard (`textInputMode`): it asks for an English one when the user has one, since a Vietnamese keyboard (Telex)
/// turns "ex" into "ẽ" even in an email field. It shows the email keyboard, suggests the user's own addresses, and
/// never corrects, capitalizes, checks spelling or swaps quotes and dashes. Its return key is Send.
///
/// It takes the keyboard only when `focusRequest` changes to a new value (the way back from the code step), never
/// when it appears.
struct EmailAddressField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// A new value puts the keyboard in the field.
    var focusRequest = 0
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EmailAddressTextField {
        let field = EmailAddressTextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.keyboardType = .emailAddress
        field.textContentType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .send
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityIdentifier = "signin.email.field"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.focusRequest = focusRequest
        return field
    }

    func updateUIView(_ field: EmailAddressTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        let category = UIContentSizeCategory(context.environment.dynamicTypeSize)
        field.font = .preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        field.isEnabled = context.environment.isEnabled
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            // After this update has laid the field out.
            Task { @MainActor in field.becomeFirstResponder() }
        }
    }

    /// As wide as offered, as high as one line of its font: a long address scrolls inside the field and never widens it.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: EmailAddressTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmailAddressField
        var focusRequest = 0

        init(_ parent: EmailAddressField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let text = field.text ?? ""
            if parent.text != text { parent.text = text }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.submit()
            return false
        }
    }
}

/// A text field that asks iOS for an English keyboard when the user has one; otherwise the system chooses, as for any
/// field. The user can still switch keyboards while typing.
final class EmailAddressTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        let modes = UITextInputMode.activeInputModes
        return EmailKeyboard.preferred(among: modes.map(\.primaryLanguage)).map { modes[$0] } ?? super.textInputMode
    }
}

/// Which keyboard the email field asks for.
enum EmailKeyboard {
    /// The index of the first English keyboard among the user's keyboards (their primary languages, such as "en-US",
    /// "vi-VN", "emoji"); nil when there is none.
    static func preferred(among languages: [String?]) -> Int? {
        languages.firstIndex { language in
            guard let language = language?.lowercased() else { return false }
            return language == "en" || language.hasPrefix("en-") || language.hasPrefix("en_")
        }
    }
}

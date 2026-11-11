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
    /// Asked at each edit; false while the code is asked for: the field then takes no edit (the request is for the address
    /// shown) and keeps the keyboard. A question, not a value, so that it is never a SwiftUI update behind the model.
    var editable: @MainActor () -> Bool = { true }
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

    /// The whole box: as wide as offered, at least 50 points high (a long address scrolls inside and never widens it).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: EmailAddressTextField, context: Context) -> CGSize? {
        field.boxSize(width: proposal.width)
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmailAddressField
        var focusRequest = 0

        init(_ parent: EmailAddressField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            // An edit that came in another way (pasted, inserted) while edits are refused is put back.
            guard parent.editable() else {
                if field.text != parent.text { field.text = parent.text }
                return
            }
            let text = field.text ?? ""
            if parent.text != text { parent.text = text }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.submit()
            return false
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            parent.editable()
        }
    }
}

/// A text field that fills the box drawn around it: its text keeps 16 points from the box's sides, and a tap anywhere
/// in the box (near its edges, in its margins) reaches the field, not only one on its line of text. Nothing takes the
/// keyboard on arrival, so the box is what the user aims at.
class BoxedTextField: UITextField {
    /// The room between the box's sides and the text.
    static let inset: CGFloat = 16
    /// The box is never lower than this; at large text sizes it grows with the font.
    static let minHeight: CGFloat = 50

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: Self.inset, dy: 0) }

    /// The box for an offered `width`: that width, one line of the font high and at least `minHeight`.
    func boxSize(width: CGFloat?) -> CGSize {
        let intrinsic = intrinsicContentSize
        return CGSize(width: width ?? intrinsic.width + 2 * Self.inset, height: max(Self.minHeight, intrinsic.height))
    }
}

/// A text field that asks iOS for an English keyboard when the user has one; otherwise the system chooses, as for any
/// field. The user can still switch keyboards while typing.
final class EmailAddressTextField: BoxedTextField {
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

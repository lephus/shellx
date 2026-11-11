import AppKit
import SwiftUI

/// A one-line AppKit field for the sign-in sheet. While it is focused, its own field editor allows only the languages
/// of the person's plain keyboard layouts (``PlainLayoutLocales``): with ABC and Vietnamese Simple Telex enabled, Telex
/// is not offered. With no plain layout there is no restriction, and the ASCII rule of ``EmailSignInModel`` is the
/// guard, as it is for paste and third-party typing tools. Autocorrection and text replacement are off; undo works.
/// Return calls `onSubmit` and Escape calls `onCancel`, except while a composition is open (the input method gets
/// those keys); the field takes the keyboard when it appears and whenever `focusRequest` changes.
///
/// ```swift
/// SignInTextField(
///     text: model.email, placeholder: texts.field, contentType: .emailAddress, font: .systemFont(ofSize: 13),
///     isEnabled: model.step == .email, focusRequest: model.focusRequest,
///     onChange: { SignInSheetFlows.setEmail(google: google, email: model, text: $0) },
///     onSubmit: { SignInSheetFlows.sendCode(google: google, email: model) },
///     onCancel: cancel
/// )
/// ```
public struct SignInTextField: NSViewRepresentable {
    private let text: String
    private let placeholder: String
    private let contentType: NSTextContentType?
    private let font: NSFont
    private let isEnabled: Bool
    private let focusRequest: Int
    private let onChange: @MainActor (String) -> Void
    private let onSubmit: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void

    /// - Parameters:
    ///   - text: The model's text; written into the field when it differs, never into an open composition.
    ///   - placeholder: Shown while the field is empty; also the field's accessibility label.
    ///   - contentType: `.emailAddress` for the address, `.oneTimeCode` for the code.
    ///   - font: The field's font (monospaced digits for the code).
    ///   - isEnabled: Whether the field takes input.
    ///   - focusRequest: The field takes the keyboard each time this changes, and when it first appears.
    ///   - onChange: Every change of the field's text.
    ///   - onSubmit: Return, outside a composition.
    ///   - onCancel: Escape, outside a composition.
    public init(
        text: String, placeholder: String, contentType: NSTextContentType?, font: NSFont, isEnabled: Bool,
        focusRequest: Int, onChange: @escaping @MainActor (String) -> Void,
        onSubmit: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void
    ) {
        self.text = text
        self.placeholder = placeholder
        self.contentType = contentType
        self.font = font
        self.isEnabled = isEnabled
        self.focusRequest = focusRequest
        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    /// The field's delegate, holding the current closures.
    ///
    /// - Returns: A coordinator for this field.
    public func makeCoordinator() -> SignInTextFieldCoordinator {
        SignInTextFieldCoordinator(onChange: onChange, onSubmit: onSubmit, onCancel: onCancel, focusRequest: focusRequest)
    }

    /// Builds the single-line field, wired to the coordinator; it takes the keyboard on its first move into a window.
    ///
    /// - Parameter context: The representable's context.
    /// - Returns: The field.
    public func makeNSView(context: Context) -> PlainLayoutTextField {
        let field = PlainLayoutTextField(frame: .zero)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.isAutomaticTextCompletionEnabled = false
        field.delegate = context.coordinator
        let coordinator = context.coordinator
        field.onFirstMoveToWindow = { coordinator.takeKeyboard($0) }
        updateNSView(field, context: context)
        return field
    }

    /// Stores the current closures in the coordinator (a reused view never calls a stale one), refreshes the
    /// placeholder, font, content type and enabled state, writes `text` when it differs and no composition is open,
    /// and takes the keyboard when `focusRequest` changed.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - context: The representable's context.
    public func updateNSView(_ field: PlainLayoutTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.onSubmit = onSubmit
        coordinator.onCancel = onCancel
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.font = font
        field.contentType = contentType
        field.isEnabled = isEnabled
        let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !isComposing, field.stringValue != text {
            field.stringValue = text
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            coordinator.takeKeyboard(field)
        }
    }
}

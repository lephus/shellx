import AppKit
import SwiftUI
import Testing
@testable import ShellXRemoteUI

/// The sign-in sheet's AppKit field, hosted in an off-screen window as
/// `SceneTextFieldAutofocusTests` (CmuxSwiftRenderUI) hosts its fields.
@MainActor @Suite("Sign-in text field", .serialized) struct SignInTextFieldTests {
    /// Stands in for another focusable view in the sheet.
    private final class StandIn: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    /// What the field's closures received.
    @MainActor private final class Events {
        var changes: [String] = []
        var submits = 0
        var cancels = 0
    }

    @MainActor private struct Harness {
        let window: NSWindow
        let standIn: StandIn
        let hosting: NSHostingView<SignInTextField>

        var field: RomanInputTextField? { SignInTextFieldTests.roman(in: hosting) }

        /// The field's own editor while it has the keyboard.
        var editor: RomanInputFieldEditor? {
            guard let field, let editor = field.currentEditor() as? RomanInputFieldEditor,
                  window.firstResponder === editor else { return nil }
            return editor
        }
    }

    private static func roman(in view: NSView) -> RomanInputTextField? {
        if let field = view as? RomanInputTextField { return field }
        for subview in view.subviews {
            if let field = roman(in: subview) { return field }
        }
        return nil
    }

    private static func window(content: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = content
        window.orderBack(nil)
        return window
    }

    private func field(_ events: Events, focusRequest: Int = 0) -> SignInTextField {
        SignInTextField(
            text: "", placeholder: "Email address", contentType: .emailAddress, font: .systemFont(ofSize: 13),
            isEnabled: true, focusRequest: focusRequest,
            onChange: { events.changes.append($0) },
            onSubmit: { events.submits += 1 },
            onCancel: { events.cancels += 1 }
        )
    }

    private func host(_ root: SignInTextField) -> Harness {
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        let standIn = StandIn(frame: NSRect(x: 0, y: 100, width: 100, height: 40))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        content.addSubview(hosting)
        content.addSubview(standIn)
        let window = Self.window(content: content)
        hosting.layoutSubtreeIfNeeded()
        return Harness(window: window, standIn: standIn, hosting: hosting)
    }

    /// One turn of host work: the run loop (SwiftUI updates) and, by suspending, the main queue, where the field's
    /// focus hop runs.
    private func turn() async {
        spinRunLoop()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    /// Synchronous on purpose: `RunLoop.run(until:)` is unavailable directly in async code.
    private func spinRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    /// Runs host turns until `condition` or a bounded deadline (test scaffolding, not runtime synchronization).
    private func pump(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            await turn()
        }
    }

    @Test func theFocusedFieldAllowsOnlyRomanInputSources() throws {
        let field = RomanInputTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let plain = NSTextField(frame: NSRect(x: 0, y: 40, width: 200, height: 24))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        content.addSubview(field)
        content.addSubview(plain)
        let window = Self.window(content: content)
        defer { window.orderOut(nil) }

        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? RomanInputFieldEditor)
        #expect(window.firstResponder === editor)
        #expect(editor.inputContext?.allowedInputSourceLocales == [NSAllRomanInputSourcesLocaleIdentifier])

        // The window's shared field editor, used by every other field, is untouched.
        #expect(window.makeFirstResponder(plain))
        let shared = try #require(plain.currentEditor() as? NSTextView)
        #expect(!(shared is RomanInputFieldEditor))
        #expect(shared.inputContext?.allowedInputSourceLocales == nil)
    }

    @Test func theEditorDoesNotCorrectAnAddress() async throws {
        let events = Events()
        let harness = host(field(events))
        defer { harness.window.orderOut(nil) }
        await pump { harness.editor != nil }
        let editor = try #require(harness.editor)
        #expect(!editor.isContinuousSpellCheckingEnabled)
        #expect(!editor.isAutomaticSpellingCorrectionEnabled)
        #expect(!editor.isAutomaticTextReplacementEnabled)
        #expect(!editor.isAutomaticQuoteSubstitutionEnabled)
        #expect(!editor.isAutomaticDashSubstitutionEnabled)
        #expect(harness.field?.contentType == .emailAddress)
    }

    @Test func typingReachesOnChange() async throws {
        let events = Events()
        let harness = host(field(events))
        defer { harness.window.orderOut(nil) }
        await pump { harness.editor != nil }
        let editor = try #require(harness.editor)
        editor.insertText("phu@", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(events.changes.last == "phu@")
    }

    @Test func returnSubmitsAndEscapeCancels() async throws {
        let events = Events()
        let harness = host(field(events))
        defer { harness.window.orderOut(nil) }
        await pump { harness.editor != nil }
        let editor = try #require(harness.editor)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(events.submits == 1)
        #expect(events.cancels == 0)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(events.cancels == 1)
    }

    @Test func returnAndEscapeWaitForAComposition() async throws {
        let events = Events()
        let harness = host(field(events))
        defer { harness.window.orderOut(nil) }
        await pump { harness.editor != nil }
        let editor = try #require(harness.editor)
        let field = try #require(harness.field)
        editor.setMarkedText(
            "´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(editor.hasMarkedText())
        // The delegate is asked directly: when it answers false, `doCommand(by:)` would run the field editor's own
        // insertNewline and end editing.
        let delegate = try #require(field.delegate)
        #expect(delegate.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
        #expect(delegate.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == false)
        #expect(events.submits == 0)
        #expect(events.cancels == 0)
        editor.unmarkText()
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(events.submits == 1)
    }

    @Test func theFieldTakesTheKeyboardWhenItAppearsAndWhenAsked() async throws {
        let first = Events(), second = Events()
        let harness = host(field(first, focusRequest: 0))
        defer { harness.window.orderOut(nil) }
        // It takes the keyboard when it appears.
        await pump { harness.editor != nil }
        let text = try #require(harness.window.firstResponder as? NSText)
        #expect(text.delegate === harness.field)

        // Then another view has it, and the sheet asks again with new closures.
        #expect(harness.window.makeFirstResponder(harness.standIn))
        #expect(harness.editor == nil)
        harness.hosting.rootView = field(second, focusRequest: 1)
        await pump { harness.editor != nil }
        let editor = try #require(harness.editor)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(second.submits == 1)
        #expect(first.submits == 0)
    }
}

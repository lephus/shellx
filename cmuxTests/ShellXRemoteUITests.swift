import AppKit
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The AppKit half of the on-site approval prompt. The model and the tracker
/// (what is shown, what may be approved) are tested in the ShellXBrand
/// package; this checks the panel itself, which no package test can reach.
@MainActor
@Suite("ShellX approval prompt panel")
struct ShellXApprovalPromptPanelTests {
    @Test("Return has no default action: the panel has no default button")
    func returnKeyHasNoDefaultAction() {
        let panel = ApprovalPromptPanel(viewModel: ApprovalPromptViewModel())
        defer { panel.orderOut(nil) }
        #expect(panel.defaultButtonCell == nil)
        // Nothing can install one either.
        panel.defaultButtonCell = NSButtonCell(textCell: "Approve")
        #expect(panel.defaultButtonCell == nil)
    }

    @Test("The panel floats, takes clicks, and cannot be closed by the user")
    func panelIsFloatingKeyAndNotClosable() {
        let panel = ApprovalPromptPanel(viewModel: ApprovalPromptViewModel())
        defer { panel.orderOut(nil) }
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.canBecomeKey)
        #expect(panel.styleMask.contains(.titled))
        #expect(!panel.styleMask.contains(.closable))
        #expect(!panel.hidesOnDeactivate)
    }

    @Test("Esc and the close command leave the panel where it is")
    func escapeAndPerformCloseDoNothing() {
        let panel = ApprovalPromptPanel(viewModel: ApprovalPromptViewModel())
        defer { panel.orderOut(nil) }
        panel.orderFront(nil)
        panel.cancelOperation(nil)
        panel.performClose(nil)
        #expect(panel.isVisible)
    }
}

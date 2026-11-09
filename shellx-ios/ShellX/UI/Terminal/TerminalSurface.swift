import ShellXAppCore
import SwiftUI

/// `TerminalSurfaceView` in SwiftUI. Its values are what `TerminalPane` read of the model, so SwiftUI calls
/// `updateUIView` after each change and the view redraws from the model. `focused` is whether it holds the keyboard.
struct TerminalSurface: UIViewRepresentable {
    let model: TerminalViewModel
    /// The terminal of the page this surface belongs to.
    let terminalId: String
    let revision: Int
    let snapshots: Int
    let topShift: Int
    let typing: TerminalTyping
    let phase: TerminalViewPhase
    let sentInputs: Int
    let title: String
    @Binding var focused: Bool

    /// What `updateUIView` last saw of `focused`.
    final class Coordinator {
        var focused = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TerminalSurfaceView {
        TerminalSurfaceView(model: model, terminalId: terminalId)
    }

    func updateUIView(_ view: TerminalSurfaceView, context: Context) {
        view.title = title
        let focus = $focused
        view.onFocusChange = { if focus.wrappedValue != $0 { focus.wrappedValue = $0 } }
        view.update(
            revision: revision, snapshots: snapshots, topShift: topShift, phase: phase, typing: typing,
            sentInputs: sentInputs)
        // The keyboard follows `focused`: the key bar's hide key sets it false; a tap on the surface sets it true. The
        // surface takes the keyboard only when `focused` turns true: after another field took it, `focused` is still
        // true until the surface's loss reaches the pane, and a redraw meanwhile (a terminal that keeps printing) must
        // not take it back.
        let turnedOn = focused && !context.coordinator.focused
        context.coordinator.focused = focused
        if !view.canBecomeFirstResponder {
            // The page stopped taking input (it reopens, the Mac went offline, a card covers it): the keyboard goes,
            // and `focused` follows when the loss reaches the pane, which hides the key bar.
            if view.isFirstResponder { view.resignFirstResponder() }
        } else if turnedOn, !view.isFirstResponder, view.window != nil {
            view.becomeFirstResponder()
        } else if !focused, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ view: TerminalSurfaceView, coordinator: Coordinator) {
        view.onFocusChange = { _ in }
        view.resignFirstResponder()
    }
}

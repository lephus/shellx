import ShellXAppCore
import SwiftUI

/// `TerminalSurfaceView` in SwiftUI. Its values are what `TerminalPane` read of the model, so SwiftUI calls
/// `updateUIView` after each change and the view redraws from the model.
struct TerminalSurface: UIViewRepresentable {
    let model: TerminalViewModel
    let revision: Int
    let snapshots: Int
    let topShift: Int
    let typing: TerminalTyping
    let phase: TerminalViewPhase
    let sentInputs: Int
    let title: String
    @Binding var focused: Bool

    func makeUIView(context: Context) -> TerminalSurfaceView {
        TerminalSurfaceView(model: model)
    }

    func updateUIView(_ view: TerminalSurfaceView, context: Context) {
        view.title = title
        let focus = $focused
        view.onFocusChange = { focus.wrappedValue = $0 }
        view.update(
            revision: revision, snapshots: snapshots, topShift: topShift, phase: phase, typing: typing,
            sentInputs: sentInputs)
    }
}

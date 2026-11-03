import SwiftUI

/// The Automations panel's content: the bundled page on the panel's background.
struct ShellXAutomationsPanelView: View {
    let panel: ShellXAutomationsPanel
    let appearance: PanelAppearance
    let onRequestPanelFocus: () -> Void

    var body: some View {
        ShellXAutomationsWebView(controller: panel.controller)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: appearance.contentBackgroundColor))
            .simultaneousGesture(TapGesture().onEnded { onRequestPanelFocus() })
            .accessibilityIdentifier("ShellXAutomationsPanel")
    }
}

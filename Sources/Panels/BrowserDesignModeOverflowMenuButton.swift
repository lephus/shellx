import SwiftUI
import ShellXIcons

struct BrowserDesignModeOverflowMenuButton: View {
    let controller: BrowserDesignModeController
    let onToggle: @MainActor () async -> Bool

    var body: some View {
        Button {
            Task { @MainActor in
                guard await onToggle() else { return }
            }
        } label: {
            ShellXLabel(
                String(localized: "browser.designMode.title", defaultValue: "Design Mode"),
                icon: "paintbrush.pointed"
            )
        }
        .disabled(!controller.canToggle)
    }
}

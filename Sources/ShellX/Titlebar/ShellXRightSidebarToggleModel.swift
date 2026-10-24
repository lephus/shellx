import Combine
import Foundation

/// State of the title bar's right sidebar button: on while the host window's
/// right sidebar is open. The accessory binds it to that window's
/// `FileExplorerState` once the window has a registered context.
final class ShellXRightSidebarToggleModel: ObservableObject {
    @Published private(set) var isOn = false
    private weak var state: FileExplorerState?
    private var visibility: AnyCancellable?

    /// Follows `state`'s visibility; nil (no window context yet) reads off.
    func bind(to state: FileExplorerState?) {
        if let state, state === self.state { return }
        self.state = state
        visibility = state?.$isVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in self?.isOn = isVisible }
        if state == nil { isOn = false }
    }
}

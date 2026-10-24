import Bonsplit

extension BonsplitConfiguration {
    /// Workspace-derived policy for a nested remote-tmux split tree.
    var remoteTmuxEmbedded: BonsplitConfiguration {
        var configuration = self
        configuration.allowSplits = true
        configuration.allowCloseLastPane = false
        configuration.allowTabReordering = false
        configuration.allowCrossPaneTabMove = false
        configuration.allowsTabContextMenu = false
        configuration.autoCloseEmptyPanes = false
        configuration.contentViewLifecycle = .keepAllAlive
        configuration.newTabPosition = .end
        configuration.tabBarVisibility = .always
        configuration.dividerPositionRange = 0...1

        configuration.appearance.minimumPaneWidth = 1
        configuration.appearance.minimumPaneHeight = 1
        configuration.appearance.tabBarLeadingInset = 0
        configuration.appearance.enableAnimations = false
        // A window has exactly one accent tab, the focused pane's of its
        // workspace (spec §6.2). The nested tree's own focused pane keeps
        // Bonsplit's default selected tab.
        configuration.appearance.selectedTabStyle = nil
        configuration.appearance.splitButtons = configuration.appearance.splitButtons.filter {
            switch $0.action {
            case .splitRight, .splitDown:
                return true
            default:
                return false
            }
        }
        return configuration
    }
}

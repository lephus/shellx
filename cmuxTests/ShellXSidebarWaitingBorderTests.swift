import AppKit
import Bonsplit
import CmuxFoundation
import CmuxSettings
import CmuxSidebar
import QuartzCore
import ShellXBrand
import SwiftUI
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A thin multicolor border runs around a sidebar row while an agent of its workspace waits for
/// the person's answer, a permission or a question (spec 2026-10-29 mobile home focus, §6.7): never
/// while the agent works, waits on background work, or is done. Under Reduce Motion the border
/// holds still in the same colors.
@Suite(.serialized)
@MainActor
struct ShellXSidebarWaitingBorderTests {
    /// The border's colors, in order around the row (spec §6.7).
    private static let stopHexes = ["#60a5fa", "#a78bfa", "#f472b6", "#fbbf24", "#60a5fa"]

    // MARK: - When the row waits

    @Test func rowWaitsOnlyWhileItsAgentNeedsInput() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        #expect(!Self.snapshot(for: workspace).agentNeedsInput, "no agent")

        let turn: [(String, AgentHibernationLifecycleState, Bool)] = [
            ("Starting", .unknown, false),
            ("Running", .running, false),
            ("Needs input", .needsInput, true),
            ("Running", .running, false),
            ("Waiting", .backgroundWorkPending, false),
            ("Needs input", .needsInput, true),
            ("Idle", .idle, false)
        ]
        for (status, lifecycle, waits) in turn {
            Self.reportAgent("claude_code", status: status, lifecycle: lifecycle, in: workspace, panelId: panelId)
            #expect(Self.snapshot(for: workspace).agentNeedsInput == waits, "\(lifecycle)")
        }
    }

    /// One pane's agent asks while another pane's works: the row waits, whatever the agent.
    @Test func rowWaitsWhileAnyPaneAsks() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let claude = try #require(workspace.focusedPanelId)
        let codex = try #require(workspace.newTerminalSplit(from: claude, orientation: .horizontal, focus: false)?.id)
        Self.reportAgent("claude_code", status: "Running", lifecycle: .running, in: workspace, panelId: claude)
        Self.reportAgent("codex", status: "Needs input", lifecycle: .needsInput, in: workspace, panelId: codex)
        #expect(Self.snapshot(for: workspace).agentNeedsInput)

        Self.reportAgent("codex", status: "Running", lifecycle: .running, in: workspace, panelId: codex)
        #expect(!Self.snapshot(for: workspace).agentNeedsInput)
    }

    /// A failure in one pane takes the status pill, but an agent that asks in another still waits.
    @Test func rowWaitsBesideAFailure() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let failed = try #require(workspace.focusedPanelId)
        let asking = try #require(workspace.newTerminalSplit(from: failed, orientation: .horizontal, focus: false)?.id)
        Self.reportAgent(
            "codex",
            status: "Failed",
            icon: "exclamationmark.triangle.fill",
            lifecycle: .idle,
            in: workspace,
            panelId: failed
        )
        Self.reportAgent("claude_code", status: "Needs input", lifecycle: .needsInput, in: workspace, panelId: asking)

        let snapshot = Self.snapshot(for: workspace)
        #expect(snapshot.statusPillGlyphKind == .error)
        #expect(snapshot.agentNeedsInput)
    }

    // MARK: - The row

    @Test func rowRunsTheBorderOnItsFillUnderItsText() throws {
        let workspaceId = UUID()
        // The same "waiting" pill on both, so only the border differs.
        let resting = Self.makeModel(workspaceId: workspaceId, agentNeedsInput: false, statusPillGlyphKind: .needsInput)
        let waiting = Self.makeModel(workspaceId: workspaceId, agentNeedsInput: true, statusPillGlyphKind: .needsInput)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: resting)
        let window = Self.layoutCell(cell, model: resting)
        defer { window.close() }
        #expect(Self.visibleBorders(in: cell).isEmpty)
        let titleView = try Self.titleView(in: cell)
        let restingTitleFrame = titleView.frame
        let restingHeight = cell.layoutContent(model: resting, width: 280, apply: false)

        Self.reconfigure(cell, with: waiting)

        let border = try #require(Self.visibleBorders(in: cell).first)
        // The flash view lies exactly on the row's fill, with the fill's corners.
        let fill = try #require(cell.subviews.compactMap { $0 as? ActivityFlashView }.first)
        #expect(border.frame == fill.frame)
        #expect(border.cornerRadius == fill.cornerRadius)
        #expect(border.cornerRadius > 0)
        // Under the row's text, and the row keeps its layout.
        let content = try #require(titleView.superview)
        let borderIndex = try #require(cell.subviews.firstIndex(of: border))
        let contentIndex = try #require(cell.subviews.firstIndex(of: content))
        #expect(borderIndex < contentIndex)
        #expect(titleView.frame == restingTitleFrame)
        #expect(cell.layoutContent(model: waiting, width: 280, apply: false) == restingHeight)

        // The answer arrives: the border goes, and nothing of it keeps moving.
        Self.reconfigure(cell, with: resting)
        #expect(Self.visibleBorders(in: cell).isEmpty)
        #expect(Self.animatingLayers(in: border).isEmpty)
    }

    /// The working shimmer and the done look are not the waiting border.
    @Test func rowHasNoBorderWhileItsAgentWorksOrIsDone() throws {
        let models = [
            Self.makeModel(agentNeedsInput: false, nameEffect: .working, statusPillGlyphKind: .running),
            Self.makeModel(agentNeedsInput: false, nameEffect: .skill(name: "review", generation: 3)),
            Self.makeModel(agentNeedsInput: false, statusPillGlyphKind: .unseen),
            Self.makeModel(agentNeedsInput: false, statusPillGlyphKind: .idle)
        ]
        for model in models {
            let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
            let window = Self.layoutCell(cell, model: model)
            #expect(Self.visibleBorders(in: cell).isEmpty)
            window.close()
        }
    }

    /// Unlike the name effects, the border is not a dark-sidebar effect: a light sidebar shows it too.
    @Test func lightSidebarShowsTheBorder() throws {
        let model = Self.makeModel(agentNeedsInput: true, colorSchemeIsDark: false)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        #expect(Self.visibleBorders(in: cell).count == 1)
    }

    @Test func presentationFlagReachesTheBorder() throws {
        let model = Self.makeModel(agentNeedsInput: true)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let border = try #require(Self.borders(in: cell).first)

        cell.setPresentationActive(false)
        #expect(!border.isPresentationActive)
        cell.setPresentationActive(true)
        #expect(border.isPresentationActive)
    }

    @Test func borderIsDecorative() throws {
        let model = Self.makeModel(agentNeedsInput: true)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }
        let border = try #require(Self.visibleBorders(in: cell).first)

        #expect(!border.isAccessibilityElement())
        #expect(border.hitTest(NSPoint(x: border.frame.midX, y: border.frame.minY + 1)) == nil)
    }

    // MARK: - The border

    @Test func borderRunsAroundOnceEveryThreeSeconds() throws {
        let environment = MotionEnvironment(reducesMotion: false)
        let (border, window) = Self.makeBorder(environment: environment)
        defer { window.close() }
        #expect(border.isHidden)
        #expect(Self.animatingLayers(in: border).isEmpty)

        border.isActive = true

        #expect(!border.isHidden)
        let turn = try #require(Self.turn(of: border))
        #expect(turn.duration == 3)
        #expect(turn.repeatCount == .infinity)
        #expect(Self.isLinear(turn.timingFunction))
        let from = try #require((turn.fromValue as? NSNumber)?.doubleValue)
        let to = try #require((turn.toValue as? NSNumber)?.doubleValue)
        #expect(abs(abs(to - from) - 2 * Double.pi) < 0.0001)
        // Only the gradient turns; the ring itself stays put.
        #expect(Self.animatingLayers(in: border).map { $0 === border.gradientLayer } == [true])
    }

    @Test func borderColorsAndRing() throws {
        let (border, window) = Self.makeBorder(environment: MotionEnvironment(reducesMotion: false))
        defer { window.close() }
        border.isActive = true

        #expect(border.gradientLayer.type == .conic)
        let colors = try #require(border.gradientLayer.colors as? [CGColor])
        #expect(colors.compactMap { NSColor(cgColor: $0).map { ShellXColor(nsColor: $0).hexString } } == Self.stopHexes)
        #expect((1.5...2).contains(border.lineWidth))
        #expect(border.cornerRadius == 6)
        // The turning gradient covers the whole row at every angle.
        let side = border.gradientLayer.bounds.width
        #expect(border.gradientLayer.bounds.height == side)
        #expect(side >= hypot(border.bounds.width, border.bounds.height))
    }

    @Test func borderHoldsStillUnderReduceMotion() throws {
        let (border, window) = Self.makeBorder(environment: MotionEnvironment(reducesMotion: true))
        defer { window.close() }

        border.isActive = true

        #expect(!border.isHidden)
        #expect(Self.animatingLayers(in: border).isEmpty)
        let colors = try #require(border.gradientLayer.colors as? [CGColor])
        #expect(colors.count == Self.stopHexes.count)
    }

    @Test func reduceMotionTurnedOnStopsARunningBorder() throws {
        let environment = MotionEnvironment(reducesMotion: false)
        let (border, window) = Self.makeBorder(environment: environment)
        defer { window.close() }
        border.isActive = true
        #expect(Self.turn(of: border) != nil)

        environment.reducesMotion = true
        Self.postAccessibilityDisplayOptionsChange()
        #expect(!border.isHidden)
        #expect(Self.animatingLayers(in: border).isEmpty)

        environment.reducesMotion = false
        Self.postAccessibilityDisplayOptionsChange()
        #expect(Self.turn(of: border) != nil)
    }

    @Test func borderStopsWhenItCannotBeSeenOrIsInactive() throws {
        let environment = MotionEnvironment(reducesMotion: false)
        let (border, window) = Self.makeBorder(environment: environment)
        defer { window.close() }
        border.isActive = true

        border.isPresentationActive = false
        #expect(Self.animatingLayers(in: border).isEmpty)
        border.isPresentationActive = true
        #expect(Self.turn(of: border) != nil)

        border.isActive = false
        #expect(border.isHidden)
        #expect(Self.animatingLayers(in: border).isEmpty)
    }

    // MARK: - Helpers

    /// An environment whose Reduce Motion setting a test can flip; the view can be seen while it is shown.
    @MainActor
    private final class MotionEnvironment: TitleEffectEnvironment {
        var reducesMotion: Bool

        init(reducesMotion: Bool) {
            self.reducesMotion = reducesMotion
        }

        func isVisible(_ view: NSView) -> Bool {
            !view.isHiddenOrHasHiddenAncestor && view.window != nil
        }
    }

    nonisolated private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ShellXSidebarWaitingBorderTests.\(UUID().uuidString)")!
    }

    /// The snapshot a dark sidebar builds for `workspace`.
    private static func snapshot(for workspace: Workspace) -> SidebarWorkspaceSnapshotBuilder.Snapshot {
        SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: SidebarTabItemSettingsSnapshot(defaults: makeDefaults()),
            showsAgentActivity: false,
            sidebarColorScheme: .dark
        ).makeSnapshot()
    }

    /// Reports an agent for the pane the way its hook CLI does: a status row and a lifecycle, with
    /// a PID to prove an agent owns the row.
    private static func reportAgent(
        _ key: String,
        status: String,
        icon: String = "bolt.fill",
        lifecycle: AgentHibernationLifecycleState,
        in workspace: Workspace,
        panelId: UUID
    ) {
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        owner.setStatusEntry(SidebarStatusEntry(key: key, value: status, icon: icon), key: key, panelId: panelId)
        owner.setAgentLifecycle(key: key, panelId: panelId, lifecycle: lifecycle)
        if workspace.agentPIDs[key] == nil {
            workspace.agentPIDs[key] = pid_t(5_000 + workspace.agentPIDs.count)
        }
    }

    private static func makeModel(
        workspaceId: UUID = UUID(),
        agentNeedsInput: Bool,
        nameEffect: AgentNameEffect? = nil,
        statusPillGlyphKind: SidebarCompactStatusGlyph.Kind? = nil,
        colorSchemeIsDark: Bool = true
    ) -> SidebarWorkspaceRowModel {
        let settings = SidebarTabItemSettingsSnapshot(defaults: makeDefaults())
        let snapshot = SidebarWorkspaceSnapshotBuilder.Snapshot(
            presentationKey: SidebarWorkspaceSnapshotFactory.presentationKey(
                settings: settings,
                showsAgentActivity: settings.details.showAgentActivity,
                customColorHex: nil
            ),
            title: "Claude session",
            customDescription: nil,
            isPinned: false,
            isMuted: false,
            customColorHex: nil,
            hasManualCustomColor: false,
            cloudWorkspaceLabel: nil,
            remoteWorkspaceSidebarText: nil,
            remoteConnectionStatusText: "",
            remoteStateHelpText: "",
            showsRemoteReconnectAffordance: false,
            copyableSidebarSSHError: nil,
            latestConversationMessage: nil,
            metadataEntries: [],
            metadataBlocks: [],
            latestLog: nil,
            progress: nil,
            activeCodingAgentCount: 0,
            compactGitBranchSummaryText: nil,
            compactDirectoryCandidates: [],
            compactBranchDirectoryCandidates: [],
            branchDirectoryLines: [],
            branchLinesContainBranch: false,
            pullRequestRows: [],
            listeningPorts: [],
            finderDirectoryPath: nil,
            mediaActivity: BrowserMediaActivity(),
            taskStatus: nil,
            todoStatusMenuModel: nil,
            hasManualTaskStatus: false,
            checklistItems: [],
            checklistCompletedCount: 0,
            checklistTotalCount: 0,
            checklistFirstUncheckedText: nil,
            statusPillGlyphKind: statusPillGlyphKind,
            nameEffect: nameEffect,
            agentActivityText: nameEffect.map { AgentActivityText().text(for: $0) },
            agentNeedsInput: agentNeedsInput
        )
        return SidebarWorkspaceRowModel(
            workspaceId: workspaceId,
            index: 0,
            snapshot: snapshot,
            settings: settings,
            isActive: false,
            isMultiSelected: false,
            hasUserCustomTitle: false,
            canCloseWorkspace: true,
            accessibilityWorkspaceCount: 1,
            unreadCount: 0,
            latestNotificationText: nil,
            showsAgentActivity: settings.details.showAgentActivity,
            rowSpacing: 8,
            isBeingDragged: false,
            topDropIndicatorVisible: false,
            bottomDropIndicatorVisible: false,
            isGrouped: false,
            isFirstRow: true,
            shortcutHintText: nil,
            showsShortcutHints: false,
            colorSchemeIsDark: colorSchemeIsDark,
            globalFontMagnificationPercent: 100,
            isChecklistExpanded: false,
            checklistAddFieldActivationToken: 0,
            isChecklistPopoverPresented: false,
            editingChecklistItemId: nil,
            todoControlsEnabled: false,
            isMetadataExpanded: false,
            isMarkdownExpanded: false
        )
    }

    /// A border the size of a sidebar row's fill, in a borderless window.
    private static func makeBorder(environment: MotionEnvironment) -> (border: WaitingBorderView, window: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 48))
        window.contentView = host
        let border = WaitingBorderView(environment: environment)
        border.cornerRadius = 6
        border.frame = NSRect(x: 6, y: 2, width: 268, height: 44)
        host.addSubview(border)
        host.layoutSubtreeIfNeeded()
        return (border, window)
    }

    /// Lays the cell out at its measured height in a borderless window, the way the table shows it.
    private static func layoutCell(
        _ cell: SidebarWorkspaceRowTableCellView,
        model: SidebarWorkspaceRowModel,
        width: CGFloat = 280
    ) -> NSWindow {
        let height = cell.layoutContent(model: model, width: width, apply: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = host
        cell.frame = host.bounds
        host.addSubview(cell)
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
        return window
    }

    /// Applies `model` the way the table updates a mounted row, then lays the row out again.
    private static func reconfigure(_ cell: SidebarWorkspaceRowTableCellView, with model: SidebarWorkspaceRowModel) {
        cell.configure(
            model: model,
            actions: SidebarAppKitRowCellTests.makeActions(model: model),
            isPointerHovering: false,
            contextMenuDidOpen: {},
            contextMenuDidClose: {}
        )
        cell.needsLayout = true
        cell.layoutSubtreeIfNeeded()
    }

    private static func titleView(in cell: SidebarWorkspaceRowTableCellView) throws -> SidebarRowTextView {
        try #require(
            SidebarAppKitRowCellTests.descendants(of: cell)
                .compactMap { $0 as? SidebarRowTextView }
                .first { !$0.isHidden && $0.stringValue == "Claude session" }
        )
    }

    private static func borders(in cell: NSView) -> [WaitingBorderView] {
        SidebarAppKitRowCellTests.descendants(of: cell).compactMap { $0 as? WaitingBorderView }
    }

    private static func visibleBorders(in cell: NSView) -> [WaitingBorderView] {
        borders(in: cell).filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    /// Every layer of the border that has an animation.
    private static func animatingLayers(in border: WaitingBorderView) -> [CALayer] {
        func layers(_ layer: CALayer) -> [CALayer] {
            [layer] + (layer.sublayers ?? []).flatMap(layers) + (layer.mask.map(layers) ?? [])
        }
        return border.layer.map(layers)?.filter { !($0.animationKeys() ?? []).isEmpty } ?? []
    }

    /// The rotation that turns the border's gradient, or `nil` while it holds still.
    private static func turn(of border: WaitingBorderView) -> CABasicAnimation? {
        let layer = border.gradientLayer
        return (layer.animationKeys() ?? [])
            .compactMap { layer.animation(forKey: $0) as? CABasicAnimation }
            .first { $0.keyPath == "transform.rotation.z" }
    }

    private static func isLinear(_ timing: CAMediaTimingFunction?) -> Bool {
        guard let timing else { return true }
        var first: [Float] = [0, 0]
        var second: [Float] = [0, 0]
        timing.getControlPoint(at: 1, values: &first)
        timing.getControlPoint(at: 2, values: &second)
        return first == [0, 0] && second == [1, 1]
    }

    private static func postAccessibilityDisplayOptionsChange() {
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
    }
}

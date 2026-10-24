import AppKit
import Bonsplit
import CmuxFoundation
import CmuxSidebar
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The session name in a sidebar row plays its agent's effect (spec 2026-10-23
/// tab selection and agent effects, §6.4 and §6.5; rulings R5, R6 and R8): a
/// moving color drawn over the name while the name keeps its text, one flash
/// over the whole row when a skill or workflow starts, the agent status line
/// saying what the agent does, and no spinner or "running" pill meanwhile.
@Suite(.serialized)
@MainActor
struct ShellXSidebarNameEffectTests {
    private static let title = "Claude session"
    private static let agentStatusKey = "claude_code"

    // MARK: - The name

    @Test func nameEffectHiddenWithoutEffect() throws {
        let model = Self.makeModel()
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        #expect(Self.effectViews(in: cell).allSatisfy { $0.isHidden })
        let titleView = try Self.titleView(in: cell)
        #expect(Self.sameColor(titleView.textColor, SidebarRowPalette(model: model).primaryText))
    }

    @Test func nameEffectShownForWorking() throws {
        let model = Self.makeModel(nameEffect: .working, agentActivityText: "Thinking…")
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        let effect = try #require(Self.effectViews(in: cell).first { !$0.isHidden })
        let titleView = try Self.titleView(in: cell)
        // The effect lies over the field's text, which NSTextField draws 2 pt in from its frame.
        #expect(effect.superview === titleView.superview)
        #expect(effect.frame == titleView.frame.insetBy(dx: 2, dy: 0))
        // The effect draws the name; the field keeps it for layout and VoiceOver.
        #expect(titleView.stringValue == Self.title)
        #expect(titleView.isAccessibilityElement())
        #expect((titleView.textColor?.alphaComponent ?? 1) == 0)
        let shown = try Self.mask(of: effect)
        let expected = try Self.referenceMask(
            text: titleView.stringValue,
            font: try #require(titleView.font),
            maximumNumberOfLines: titleView.maximumNumberOfLines,
            size: effect.frame.size,
            in: window
        )
        #expect(shown == expected)
    }

    @Test func nameEffectMatchesWrappedTitle() throws {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "sidebarWrapWorkspaceTitles")
        let longTitle = "A long session name that wraps over several lines in a narrow sidebar"
        let model = Self.makeModel(
            title: longTitle,
            nameEffect: .skill(name: "brainstorming", generation: 1),
            agentActivityText: "Skill · brainstorming",
            defaults: defaults
        )
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model, width: 200)
        defer { window.close() }

        let titleView = try #require(
            SidebarAppKitRowCellTests.descendants(of: cell)
                .compactMap { $0 as? SidebarRowTextView }
                .first { !$0.isHidden && $0.stringValue == longTitle }
        )
        let font = try #require(titleView.font)
        #expect(titleView.maximumNumberOfLines == 8)
        // The name really wraps at this width, so a one-line effect would draw it differently.
        #expect(titleView.frame.height > ceil(font.ascender - font.descender + font.leading) * 1.5)

        let effect = try #require(Self.effectViews(in: cell).first { !$0.isHidden })
        #expect(effect.frame == titleView.frame.insetBy(dx: 2, dy: 0))
        let shown = try Self.mask(of: effect)
        let sameLines = try Self.referenceMask(
            text: longTitle,
            font: font,
            maximumNumberOfLines: titleView.maximumNumberOfLines,
            size: effect.frame.size,
            in: window
        )
        let oneLine = try Self.referenceMask(
            text: longTitle,
            font: font,
            maximumNumberOfLines: 1,
            size: effect.frame.size,
            in: window
        )
        #expect(shown == sameLines)
        #expect(shown != oneLine)
    }

    @Test func nameEffectHidesDuringInlineRename() throws {
        let model = Self.makeModel(
            nameEffect: .workflow(name: "release", generation: 2),
            agentActivityText: "Workflow · release"
        )
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        window.orderFront(nil)
        defer { window.close() }
        let effect = try #require(Self.effectViews(in: cell).first { !$0.isHidden })

        cell.beginInlineRename()

        #expect(cell.isEditing)
        #expect(effect.isHidden)

        let editor = try #require(window.firstResponder as? NSTextView)
        // The shared rename coordinator moves the caret on the first Escape and cancels on the second.
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        #expect(!cell.isEditing)
        #expect(!effect.isHidden)
    }

    @Test func nameEffectHiddenOnLightSidebar() throws {
        let model = Self.makeModel(
            nameEffect: .working,
            agentActivityText: "Thinking…",
            metadataEntries: [Self.agentRunningEntry],
            activeCodingAgentCount: 1,
            statusPillGlyphKind: .running,
            colorSchemeIsDark: false
        )
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        // A light sidebar keeps today's row (R6): no effect, the usual name
        // color, spinner and pill, and the agent row's own text and icon.
        #expect(Self.effectViews(in: cell).allSatisfy { $0.isHidden })
        let titleView = try Self.titleView(in: cell)
        #expect(Self.sameColor(titleView.textColor, SidebarRowPalette(model: model).primaryText))
        #expect(Self.visibleSpinners(in: cell).count == 1)
        #expect(Self.pill(in: cell) == .running)
        let row = try #require(Self.visibleMetadataRows(in: cell).first)
        #expect(Self.visibleTexts(in: row) == ["Running"])
        #expect(Self.visibleGlyphs(in: row).isEmpty)
    }

    // MARK: - The flash

    @Test func skillFlashCoversTheRow() throws {
        let model = Self.makeModel(
            nameEffect: .skill(name: "brainstorming", generation: 3),
            agentActivityText: "Skill · brainstorming"
        )
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let width: CGFloat = 280
        let window = Self.layoutCell(cell, model: model, width: width)
        defer { window.close() }

        let flash = try #require(cell.subviews.compactMap { $0 as? ActivityFlashView }.first)
        let pad = SidebarWorkspaceListMetrics.rowOuterHorizontalPadding
        #expect(flash.frame.minX == pad)
        #expect(flash.frame.minY == 0)
        #expect(flash.frame.width == width - 2 * pad)
        #expect(abs(flash.frame.height - cell.bounds.height) < 1)
        #expect(flash.cornerRadius == 6)
        // Above the row's fill, below its content.
        let flashIndex = try #require(cell.subviews.firstIndex { $0 === flash })
        let contentIndex = try #require(cell.subviews.firstIndex { $0 is SidebarRowContentContainerView })
        #expect(flashIndex < contentIndex)
        #expect(flash.flashedGeneration == 3)
    }

    // MARK: - The agent status line

    @Test func activityTextReplacesAgentStatusRow() throws {
        let entries = [
            Self.agentRunningEntry,
            SidebarStatusEntry(key: "build", value: "Passing", icon: "hammer.fill")
        ]
        let model = Self.makeModel(nameEffect: .working, agentActivityText: "Thinking…", metadataEntries: entries)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        let rows = Self.visibleMetadataRows(in: cell)
        #expect(rows.count == 2)
        let agentRow = try #require(rows.first)
        #expect(Self.visibleTexts(in: agentRow) == ["Thinking…"])
        // The ✻ glyph takes the place of the row's icon.
        #expect(Self.visibleGlyphs(in: agentRow).count == 1)
        #expect(Self.visibleImages(in: agentRow).isEmpty)
        // Other rows keep their own text and icon.
        let otherRow = try #require(rows.last)
        #expect(Self.visibleTexts(in: otherRow) == ["Passing"])
        #expect(Self.visibleGlyphs(in: otherRow).isEmpty)

        // When the effect ends, the agent row says its own status again.
        let ended = Self.makeModel(workspaceId: model.workspaceId, metadataEntries: entries)
        cell.configure(
            model: ended,
            actions: SidebarAppKitRowCellTests.makeActions(model: ended),
            isPointerHovering: false,
            contextMenuDidOpen: {},
            contextMenuDidClose: {}
        )
        cell.layoutSubtreeIfNeeded()
        let restored = try #require(Self.visibleMetadataRows(in: cell).first)
        #expect(Self.visibleTexts(in: restored) == ["Running"])
        #expect(Self.visibleGlyphs(in: restored).isEmpty)
        #expect(Self.visibleImages(in: restored).count == 1)
    }

    @Test func noNewRowWhenMetadataHidden() throws {
        let metadataOff = Self.makeDefaults()
        metadataOff.set(false, forKey: "sidebarShowStatusPills")
        let cases: [(entries: [SidebarStatusEntry], defaults: UserDefaults)] = [
            ([], Self.makeDefaults()),
            ([Self.agentRunningEntry], metadataOff)
        ]
        for (entries, defaults) in cases {
            let plainModel = Self.makeModel(metadataEntries: entries, defaults: defaults)
            let effectModel = Self.makeModel(
                nameEffect: .skill(name: "review", generation: 4),
                agentActivityText: "Skill · review",
                metadataEntries: entries,
                defaults: defaults
            )
            let plain = SidebarAppKitRowCellTests.configuredCell(model: plainModel)
            let withEffect = SidebarAppKitRowCellTests.configuredCell(model: effectModel)

            #expect(Self.visibleMetadataRows(in: withEffect).count == Self.visibleMetadataRows(in: plain).count)
            #expect(Self.visibleMetadataRows(in: withEffect).isEmpty)
            #expect(
                withEffect.layoutContent(model: effectModel, width: 280, apply: false)
                    == plain.layoutContent(model: plainModel, width: 280, apply: false)
            )
        }
    }

    // MARK: - Spinner and pills (R5)

    @Test func effectHidesSpinnerAndRunningPill() throws {
        let plain = SidebarAppKitRowCellTests.configuredCell(
            model: Self.makeModel(activeCodingAgentCount: 1, statusPillGlyphKind: .running)
        )
        #expect(Self.visibleSpinners(in: plain).count == 1)
        #expect(Self.pill(in: plain) == .running)

        let working = SidebarAppKitRowCellTests.configuredCell(
            model: Self.makeModel(
                nameEffect: .working,
                agentActivityText: "Thinking…",
                activeCodingAgentCount: 1,
                statusPillGlyphKind: .running
            )
        )
        #expect(Self.visibleSpinners(in: working).isEmpty)
        #expect(Self.pill(in: working) == nil)

        // Waiting for you, done and error stay: the effect stands in for "running" only.
        let kept: [(SidebarCompactStatusGlyph.Kind, SidebarStatusPill)] = [
            (.needsInput, .waiting),
            (.unseen, .done),
            (.error, .error)
        ]
        for (kind, pill) in kept {
            let cell = SidebarAppKitRowCellTests.configuredCell(
                model: Self.makeModel(
                    nameEffect: .skill(name: "review", generation: 1),
                    agentActivityText: "Skill · review",
                    activeCodingAgentCount: 1,
                    statusPillGlyphKind: kind
                )
            )
            #expect(Self.pill(in: cell) == pill)
            #expect(Self.visibleSpinners(in: cell).isEmpty)
        }
    }

    // MARK: - Group headers (R8)

    @Test func groupHeaderHasNoNameEffect() {
        let cell = SidebarGroupHeaderTableCellView()
        cell.configurePresentation(
            model: ShellXSidebarSelectionTests.groupHeaderModel(isAnchorActive: true, anchorActiveSelectionTint: nil)
        )

        let effects = SidebarAppKitRowCellTests.descendants(of: cell).filter {
            $0 is TitleEffectView || $0 is ActivityFlashView || $0 is ActivityGlyphView
        }
        #expect(effects.isEmpty)
    }

    // MARK: - Helpers

    private static let agentRunningEntry = SidebarStatusEntry(
        key: ShellXSidebarNameEffectTests.agentStatusKey,
        value: "Running",
        icon: "bolt.fill"
    )

    /// Colors and timing for reference masks; the mask is the same whatever the colors.
    private static let style = TitleEffectStyle(
        workingBaseHex: "#b39550",
        workingHighlightHex: "#fff3cf",
        glyphWorkingHex: "#e8c468",
        flashHex: "#d6c4ff42",
        highlightStopHexes: ["#f4a7c0", "#f2c879", "#8fd9a8", "#7cc8e8", "#9fb0f5", "#c9a7f2", "#f4a7c0"]
    )

    nonisolated private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ShellXSidebarNameEffectTests.\(UUID().uuidString)")!
    }

    private static func makeModel(
        workspaceId: UUID = UUID(),
        title: String = ShellXSidebarNameEffectTests.title,
        nameEffect: AgentNameEffect? = nil,
        agentActivityText: String? = nil,
        metadataEntries: [SidebarStatusEntry] = [],
        activeCodingAgentCount: Int = 0,
        statusPillGlyphKind: SidebarCompactStatusGlyph.Kind? = nil,
        defaults: UserDefaults = ShellXSidebarNameEffectTests.makeDefaults(),
        colorSchemeIsDark: Bool = true
    ) -> SidebarWorkspaceRowModel {
        let settings = SidebarTabItemSettingsSnapshot(defaults: defaults)
        let snapshot = SidebarWorkspaceSnapshotBuilder.Snapshot(
            presentationKey: SidebarWorkspaceSnapshotFactory.presentationKey(
                settings: settings,
                showsAgentActivity: settings.details.showAgentActivity,
                customColorHex: nil
            ),
            title: title,
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
            metadataEntries: metadataEntries,
            metadataBlocks: [],
            latestLog: nil,
            progress: nil,
            activeCodingAgentCount: activeCodingAgentCount,
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
            agentActivityText: agentActivityText
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

    private static func titleView(in cell: SidebarWorkspaceRowTableCellView) throws -> SidebarRowTextView {
        try #require(
            SidebarAppKitRowCellTests.descendants(of: cell)
                .compactMap { $0 as? SidebarRowTextView }
                .first { !$0.isHidden && $0.stringValue == title }
        )
    }

    private static func effectViews(in cell: NSView) -> [TitleEffectView] {
        SidebarAppKitRowCellTests.descendants(of: cell).compactMap { $0 as? TitleEffectView }
    }

    private static func visibleSpinners(in cell: NSView) -> [GPUSpinnerNSView] {
        SidebarAppKitRowCellTests.descendants(of: cell)
            .compactMap { $0 as? GPUSpinnerNSView }
            .filter { !$0.isHiddenOrHasHiddenAncestor }
    }

    private static func pill(in cell: NSView) -> SidebarStatusPill? {
        let view = SidebarAppKitRowCellTests.descendants(of: cell).compactMap { $0 as? SidebarStatusPillView }.first
        guard let view, !view.isHidden else { return nil }
        return view.pill
    }

    private static func visibleMetadataRows(in cell: SidebarWorkspaceRowTableCellView) -> [SidebarRowIconTextLine] {
        SidebarAppKitRowCellTests.descendants(of: cell)
            .compactMap { $0 as? SidebarRowIconTextLine }
            .filter { !$0.isHidden }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private static func visibleTexts(in row: SidebarRowIconTextLine) -> [String] {
        row.subviews.compactMap { $0 as? SidebarRowTextView }.filter { !$0.isHidden }.map { $0.stringValue }
    }

    private static func visibleGlyphs(in row: SidebarRowIconTextLine) -> [ActivityGlyphView] {
        row.subviews.compactMap { $0 as? ActivityGlyphView }.filter { !$0.isHidden }
    }

    private static func visibleImages(in row: SidebarRowIconTextLine) -> [NSImageView] {
        row.subviews.compactMap { $0 as? NSImageView }.filter { !$0.isHidden }
    }

    private static func sameColor(_ lhs: NSColor?, _ rhs: NSColor) -> Bool {
        guard let left = lhs?.usingColorSpace(.sRGB), let right = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }

    /// The pixels of an effect's text mask, which depend on its text, font, line limit and size only.
    private struct MaskPixels: Equatable {
        let width: Int
        let height: Int
        let bytes: Data
    }

    private static func mask(of effect: TitleEffectView) throws -> MaskPixels {
        let gradient = try #require(effect.layer?.sublayers?.first { $0.mask != nil })
        let contents = try #require(gradient.mask?.contents)
        let image = contents as! CGImage
        let data = try #require(image.dataProvider?.data) as Data
        return MaskPixels(width: image.width, height: image.height, bytes: data)
    }

    /// The mask a fresh effect view draws for `text` at `size`, in the same window and so at the same scale.
    private static func referenceMask(
        text: String,
        font: NSFont,
        maximumNumberOfLines: Int,
        size: CGSize,
        in window: NSWindow
    ) throws -> MaskPixels {
        let reference = TitleEffectView()
        reference.frame = NSRect(origin: .zero, size: size)
        let host = try #require(window.contentView)
        host.addSubview(reference)
        defer { reference.removeFromSuperview() }
        reference.configure(
            text: NSAttributedString(string: text, attributes: [.font: font]),
            maximumNumberOfLines: maximumNumberOfLines,
            kind: .working,
            style: style
        )
        return try mask(of: reference)
    }
}

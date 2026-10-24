import AppKit
import Bonsplit
import CmuxFoundation
import CmuxSettings
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

    @Test func wrappedTitleKeepsItsWidthAndRowHeightWhenTheEffectStartsAndEnds() throws {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "sidebarWrapWorkspaceTitles")
        let longTitle = "A long session name that wraps over several lines in a narrow sidebar"
        let workspaceId = UUID()
        func model(_ effect: AgentNameEffect?) -> SidebarWorkspaceRowModel {
            Self.makeModel(
                workspaceId: workspaceId,
                title: longTitle,
                nameEffect: effect,
                agentActivityText: effect == nil ? nil : "Thinking…",
                metadataEntries: [Self.agentRunningEntry],
                activeCodingAgentCount: 1,
                statusPillGlyphKind: .running,
                defaults: defaults
            )
        }
        let width: CGFloat = 220
        let running = model(nil)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: running)
        let window = Self.layoutCell(cell, model: running, width: width)
        defer { window.close() }
        let titleView = try #require(
            SidebarAppKitRowCellTests.descendants(of: cell)
                .compactMap { $0 as? SidebarRowTextView }
                .first { !$0.isHidden && $0.stringValue == longTitle }
        )
        #expect(Self.visibleSpinners(in: cell).count == 1)
        #expect(Self.pill(in: cell) == .running)
        let runningFrame = titleView.frame
        let runningHeight = cell.layoutContent(model: running, width: width, apply: false)

        let effects: [AgentNameEffect?] = [.working, .skill(name: "review", generation: 5), nil]
        for effect in effects {
            let next = model(effect)
            Self.reconfigure(cell, with: next)
            // The spinner and the pill hide, but the name keeps their space.
            #expect(titleView.frame == runningFrame)
            #expect(cell.layoutContent(model: next, width: width, apply: false) == runningHeight)
            #expect(Self.visibleSpinners(in: cell).count == (effect == nil ? 1 : 0))
            #expect(Self.pill(in: cell) == (effect == nil ? SidebarStatusPill.running : nil))
        }

        // A one-line name takes the space back.
        let oneLineRunning = Self.makeModel(activeCodingAgentCount: 1, statusPillGlyphKind: .running)
        let oneLine = SidebarAppKitRowCellTests.configuredCell(model: oneLineRunning)
        let oneLineWindow = Self.layoutCell(oneLine, model: oneLineRunning, width: width)
        defer { oneLineWindow.close() }
        let oneLineTitle = try Self.titleView(in: oneLine)
        let oneLineWidth = oneLineTitle.frame.width
        Self.reconfigure(
            oneLine,
            with: Self.makeModel(
                workspaceId: oneLineRunning.workspaceId,
                nameEffect: .working,
                agentActivityText: "Thinking…",
                activeCodingAgentCount: 1,
                statusPillGlyphKind: .running
            )
        )
        #expect(oneLineTitle.frame.width > oneLineWidth)
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

    @Test func flashPlaysOnceForANewSkillAndNeverForAReusedRow() throws {
        let (presenter, window) = Self.makePresenter()
        defer { window.close() }
        let flash = presenter.flashView
        let row = UUID()

        // The skill started before the row showed it: that moment has passed.
        presenter.apply(effect: .skill(name: "review", generation: 3), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(!Self.isFlashing(flash))

        // A new skill on the same row flashes once.
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(Self.isFlashing(flash))
        Self.stopFlash(flash)
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)
        presenter.apply(effect: .working, isRenaming: false, style: Self.style, rowIdentity: row)
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(!Self.isFlashing(flash))

        // Reused for another workspace, the row does not flash for the workflow that already runs there.
        presenter.apply(
            effect: .workflow(name: "release", generation: 9),
            isRenaming: false,
            style: Self.style,
            rowIdentity: UUID()
        )
        #expect(!Self.isFlashing(flash))
        #expect(flash.flashedGeneration == 9)
    }

    /// A row shows its workspace's strongest effect, which can fall back to an older skill or
    /// workflow from another pane (spec §6.3). The flash belongs to the start of a skill or workflow
    /// (§6.4), so a generation the row already showed, or one older than it, never flashes again.
    @Test func flashNeverReplaysAnOlderGeneration() throws {
        let (presenter, window) = Self.makePresenter()
        defer { window.close() }
        let flash = presenter.flashView
        let row = UUID()
        presenter.apply(effect: .working, isRenaming: false, style: Self.style, rowIdentity: row)

        // Pane B starts a skill: new, so it flashes.
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(Self.isFlashing(flash))
        Self.stopFlash(flash)

        // B stops to ask for permission: the row falls back to pane A's older background workflow.
        presenter.apply(
            effect: .workflow(name: "release", generation: 3),
            isRenaming: false,
            style: Self.style,
            rowIdentity: row
        )
        #expect(!Self.isFlashing(flash))

        // B resumes the same skill.
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(!Self.isFlashing(flash))

        // A skill that really starts now still flashes.
        presenter.apply(effect: .skill(name: "review", generation: 5), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(Self.isFlashing(flash))
    }

    /// A light sidebar plays no effect (R6): its cell gives the presenter neither effect nor style.
    /// A skill that started meanwhile does not flash when the sidebar turns dark again.
    @Test func switchingToADarkSidebarMidSkillDoesNotFlash() throws {
        let (presenter, window) = Self.makePresenter()
        defer { window.close() }
        let flash = presenter.flashView
        let row = UUID()
        presenter.apply(effect: .working, isRenaming: false, style: Self.style, rowIdentity: row)
        presenter.apply(effect: nil, isRenaming: false, style: nil, rowIdentity: row)

        presenter.apply(effect: .skill(name: "review", generation: 6), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(!Self.isFlashing(flash))

        presenter.apply(effect: .skill(name: "review", generation: 7), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(Self.isFlashing(flash))
    }

    /// A reused cell can come back for the same workspace after a skill started there while the
    /// row was away; that start already passed, so it does not flash late (the cell calls
    /// `forgetRow()` from `prepareForReuse`).
    @Test func reusedRowDoesNotFlashForAStartItNeverShowed() throws {
        let (presenter, window) = Self.makePresenter()
        defer { window.close() }
        let flash = presenter.flashView
        let row = UUID()
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: row)

        presenter.forgetRow()
        presenter.apply(effect: .skill(name: "review", generation: 5), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(!Self.isFlashing(flash))
        #expect(flash.flashedGeneration == 5)

        // Once shown again, the row flashes for the next start.
        presenter.apply(effect: .workflow(name: "release", generation: 6), isRenaming: false, style: Self.style, rowIdentity: row)
        #expect(Self.isFlashing(flash))
    }

    /// A flash still waiting for the window belongs to the workspace that started it. Generations
    /// count per workspace, so the row's next workspace can play the same number; reused for it,
    /// the row must not play the old workspace's flash.
    @Test func reusedRowDropsTheOldWorkspacesWaitingFlash() throws {
        let (presenter, window) = Self.makePresenter()
        defer { window.close() }
        let flash = presenter.flashView
        let host = try #require(flash.superview)
        let first = UUID()
        presenter.apply(effect: .working, isRenaming: false, style: Self.style, rowIdentity: first)
        // Off screen, a new skill's flash waits for the window.
        flash.removeFromSuperview()
        presenter.apply(effect: .skill(name: "review", generation: 4), isRenaming: false, style: Self.style, rowIdentity: first)

        presenter.forgetRow()
        presenter.apply(effect: .skill(name: "ship", generation: 4), isRenaming: false, style: Self.style, rowIdentity: UUID())
        host.addSubview(flash, positioned: .below, relativeTo: nil)
        flash.frame = host.bounds

        #expect(!Self.isFlashing(flash))
    }

    @Test func presentationFlagReachesEveryEffectView() throws {
        let model = Self.makeModel(
            nameEffect: .working,
            agentActivityText: "Thinking…",
            metadataEntries: [Self.agentRunningEntry]
        )
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let effect = try #require(Self.effectViews(in: cell).first)
        let flash = try #require(cell.subviews.compactMap { $0 as? ActivityFlashView }.first)
        let glyph = try #require(
            SidebarAppKitRowCellTests.descendants(of: cell).compactMap { $0 as? ActivityGlyphView }.first
        )

        cell.setPresentationActive(false)
        #expect(!effect.isPresentationActive)
        #expect(!flash.isPresentationActive)
        #expect(!glyph.isPresentationActive)

        cell.setPresentationActive(true)
        #expect(effect.isPresentationActive)
        #expect(flash.isPresentationActive)
        #expect(glyph.isPresentationActive)
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

    /// The activity goes on the row of the agent whose work drives the effect (spec §6.5): Codex
    /// has no skills or workflows, but its turns work like Claude's (§6.3).
    @Test func codexSessionSaysWhatItDoesOnItsOwnRow() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        Self.reportAgent("codex", status: "Running", lifecycle: .running, in: workspace, panelId: panelId)

        let model = Self.rowModel(for: workspace)
        #expect(model.snapshot.nameEffect == .working)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        let rows = Self.visibleMetadataRows(in: cell)
        #expect(rows.map { Self.visibleTexts(in: $0) } == [[AgentActivityText().text(for: .working)]])
        #expect(rows.map { Self.visibleGlyphs(in: $0).count } == [1])
    }

    /// Claude waits for the person while Codex works: Codex drives the effect, so its row says what
    /// it does, and Claude's row keeps saying that it waits.
    @Test func mixedSessionKeepsEachAgentOnItsOwnRow() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let claude = try #require(workspace.focusedPanelId)
        let codex = try #require(workspace.newTerminalSplit(from: claude, orientation: .horizontal, focus: false)?.id)
        Self.reportAgent(
            "claude_code",
            status: "Needs input",
            icon: "bell.fill",
            workState: nil,
            lifecycle: .needsInput,
            in: workspace,
            panelId: claude
        )
        Self.reportAgent("codex", status: "Running", lifecycle: .running, in: workspace, panelId: codex)

        let model = Self.rowModel(for: workspace)
        #expect(model.snapshot.nameEffect == .working)
        let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
        let window = Self.layoutCell(cell, model: model)
        defer { window.close() }

        let rows = Self.visibleMetadataRows(in: cell)
        #expect(rows.count == 2)
        let waiting = try #require(rows.first { Self.visibleTexts(in: $0) == ["Needs input"] })
        #expect(Self.visibleGlyphs(in: waiting).isEmpty)
        let working = try #require(rows.first { Self.visibleTexts(in: $0) == [AgentActivityText().text(for: .working)] })
        #expect(Self.visibleGlyphs(in: working).count == 1)
    }

    /// Claude Code also reports its turn over OSC 7501 ("claude-code · Working"). That row stays its
    /// own line, next to the hook's `claude_code` row, which says what Claude does: the effect adds
    /// and removes no line.
    @Test func claudeProgramStatusStaysItsOwnRowDuringATurn() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)
        Self.reportAgent("claude_code", status: "Running", lifecycle: .running, in: workspace, panelId: panelId)

        let turn = Self.rowModel(for: workspace)
        #expect(turn.snapshot.nameEffect == .working)
        #expect(turn.snapshot.agentActivityStatusKey == "claude_code")
        let cell = SidebarAppKitRowCellTests.configuredCell(model: turn)
        let window = Self.layoutCell(cell, model: turn)
        defer { window.close() }
        let rows = Self.visibleMetadataRows(in: cell).map { Self.visibleTexts(in: $0) }
        #expect(rows.count == 2)
        #expect(rows.contains([AgentActivityText().text(for: .working)]))
        #expect(rows.contains { $0.joined(separator: " ").contains("claude-code") })
    }

    /// Claude Code leaves a "claude-code · Done" record after each turn. The session row has the
    /// same lines before a turn, during it, under a skill, after Stop and in the next turn, so it
    /// never changes height (the review's N1).
    @Test func rowKeepsItsHeightAcrossClaudeTurns() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(ProgramStatusReport(state: .done, app: "claude-code"), panelId: panelId)
        Self.reportAgent(
            "claude_code",
            status: "Idle",
            icon: "pause.circle.fill",
            workState: nil,
            lifecycle: .idle,
            in: workspace,
            panelId: panelId
        )

        func measure(_ step: String) -> (lines: Int, height: CGFloat) {
            let model = Self.rowModel(for: workspace)
            let cell = SidebarAppKitRowCellTests.configuredCell(model: model)
            let window = Self.layoutCell(cell, model: model)
            defer { window.close() }
            return (Self.visibleMetadataRows(in: cell).count, cell.layoutContent(model: model, width: 280, apply: false))
        }

        let before = measure("before")
        #expect(before.lines == 2)
        var seen: [(String, (lines: Int, height: CGFloat))] = []

        func startTurn() {
            workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)
            Self.reportAgent("claude_code", status: "Running", lifecycle: .running, in: workspace, panelId: panelId)
            workspace.applyAgentActivity(.turnStarted(slashCommandName: nil), surfaceId: panelId)
        }
        func stopTurn() {
            workspace.applyAgentActivity(.turnEnded(hasBackgroundWork: false), surfaceId: panelId)
            workspace.applyProgramStatus(ProgramStatusReport(state: .done, app: "claude-code"), panelId: panelId)
            Self.reportAgent(
                "claude_code",
                status: "Idle",
                icon: "pause.circle.fill",
                workState: nil,
                lifecycle: .idle,
                in: workspace,
                panelId: panelId
            )
        }

        startTurn()
        seen.append(("turn start", measure("turn start")))
        workspace.applyAgentActivity(.skillInvoked(name: "review"), surfaceId: panelId)
        seen.append(("skill", measure("skill")))
        stopTurn()
        seen.append(("stop", measure("stop")))
        startTurn()
        seen.append(("next turn", measure("next turn")))

        for (step, measured) in seen {
            #expect(measured.lines == before.lines, "\(step): line count")
            #expect(measured.height == before.height, "\(step): height")
        }
    }

    /// With metadata hidden or compact status on there is no activity row, only the name plays
    /// (spec §6.5); the rows the person sees stay as they were.
    @Test func noActivityRowWithoutAgentRows() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelId = try #require(workspace.focusedPanelId)
        workspace.applyProgramStatus(ProgramStatusReport(state: .working, app: "claude-code"), panelId: panelId)
        Self.reportAgent("claude_code", status: "Running", lifecycle: .running, in: workspace, panelId: panelId)

        let shown = Self.rowModel(for: workspace).snapshot
        #expect(shown.agentActivityStatusKey == "claude_code")
        #expect(Set(shown.metadataEntries.map(\.key)) == [Workspace.programStatusKey, "claude_code"])

        let compact = Self.rowModel(for: workspace) { $0.set(true, forKey: "sidebarCompactAgentStatus") }.snapshot
        #expect(compact.nameEffect == .working)
        #expect(compact.agentActivityStatusKey == nil)
        #expect(compact.metadataEntries.map(\.key).contains(Workspace.programStatusKey))

        let hidden = Self.rowModel(for: workspace) { $0.set(false, forKey: "sidebarShowStatusPills") }.snapshot
        #expect(hidden.nameEffect == .working)
        #expect(hidden.agentActivityStatusKey == nil)
        #expect(hidden.metadataEntries.isEmpty)
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
        agentActivityStatusKey: String? = ShellXSidebarNameEffectTests.agentStatusKey,
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
            agentActivityText: agentActivityText,
            // As the snapshot factory does: the agent's row says what it does only while there is an effect.
            agentActivityStatusKey: nameEffect == nil ? nil : agentActivityStatusKey
        )
        return rowModel(
            snapshot: snapshot,
            settings: settings,
            workspaceId: workspaceId,
            colorSchemeIsDark: colorSchemeIsDark
        )
    }

    /// The row a dark sidebar shows for `workspace`, with its snapshot built the way the sidebar builds it.
    private static func rowModel(
        for workspace: Workspace,
        configure: (UserDefaults) -> Void = { _ in }
    ) -> SidebarWorkspaceRowModel {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SidebarCatalogSection().showAgentActivity.userDefaultsKey)
        // Only status rows: the working directory line is a row of the same kind.
        defaults.set(false, forKey: SidebarCatalogSection().showBranchDirectory.userDefaultsKey)
        configure(defaults)
        let settings = SidebarTabItemSettingsSnapshot(defaults: defaults)
        // `showsAgentActivity` stays off: in ShellX the spinner also needs an experiment flag that
        // is off, and name effects follow the setting alone.
        let snapshot = SidebarWorkspaceSnapshotFactory(
            workspace: workspace,
            settings: settings,
            showsAgentActivity: false,
            sidebarColorScheme: .dark
        ).makeSnapshot()
        return rowModel(snapshot: snapshot, settings: settings, workspaceId: workspace.id, colorSchemeIsDark: true)
    }

    private static func rowModel(
        snapshot: SidebarWorkspaceSnapshotBuilder.Snapshot,
        settings: SidebarTabItemSettingsSnapshot,
        workspaceId: UUID,
        colorSchemeIsDark: Bool
    ) -> SidebarWorkspaceRowModel {
        SidebarWorkspaceRowModel(
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

    /// Reports an agent's turn for the pane the way its hook CLI does: a `set_status` row and a
    /// lifecycle. A structured agent row shows only while something proves an agent owns it; a PID
    /// is the smallest such proof.
    private static func reportAgent(
        _ key: String,
        status: String,
        icon: String = "bolt.fill",
        workState: SidebarAgentWorkState? = .running,
        lifecycle: AgentHibernationLifecycleState,
        in workspace: Workspace,
        panelId: UUID
    ) {
        let owner = ControlSidebarPanelOwner.workspace(workspace)
        owner.setStatusEntry(
            SidebarStatusEntry(key: key, value: status, icon: icon, workState: workState),
            key: key,
            panelId: panelId
        )
        owner.setAgentLifecycle(key: key, panelId: panelId, lifecycle: lifecycle)
        if workspace.agentPIDs[key] == nil {
            workspace.agentPIDs[key] = pid_t(4_000 + workspace.agentPIDs.count)
        }
    }

    /// A presenter over a session name in a borderless window, where its flash can play.
    private static func makePresenter() -> (presenter: SidebarRowNameEffectPresenter, window: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))
        window.contentView = host
        let titleView = SidebarRowTextView(lines: 1)
        titleView.stringValue = title
        titleView.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleView.frame = NSRect(x: 10, y: 8, width: 200, height: 16)
        host.addSubview(titleView)
        let presenter = SidebarRowNameEffectPresenter(
            titleView: titleView,
            host: host,
            environment: VisibleEnvironment()
        )
        host.addSubview(presenter.flashView, positioned: .below, relativeTo: titleView)
        presenter.flashView.frame = host.bounds
        return (presenter, window)
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

    /// An environment where the effect views can be seen and may move.
    private struct VisibleEnvironment: TitleEffectEnvironment {
        var reducesMotion: Bool { false }

        func isVisible(_ view: NSView) -> Bool { true }
    }

    /// Whether the flash view's wash is animating.
    private static func isFlashing(_ flash: ActivityFlashView) -> Bool {
        (flash.layer?.sublayers ?? []).contains { !($0.animationKeys() ?? []).isEmpty }
    }

    private static func stopFlash(_ flash: ActivityFlashView) {
        flash.layer?.sublayers?.forEach { $0.removeAllAnimations() }
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

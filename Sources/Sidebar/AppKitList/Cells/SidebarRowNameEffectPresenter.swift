import AppKit
import Bonsplit
import CmuxSidebar
import Foundation
import SwiftUI

/// Plays a coding agent's effect on a sidebar session name (spec 2026-10-23 tab selection and
/// agent effects, §6.4): a gold sweep while the agent works, flowing pastels while it runs a skill
/// or a workflow, and one flash over the whole row when the skill or workflow starts.
///
/// The name stays an `NSTextField`, so it keeps its layout and its accessibility text: while an
/// effect plays, the field's text turns clear and a ``TitleEffectView`` draws the same text over
/// it, framed on the field's text 2 pt in from its frame. The effect hides while the name is being
/// renamed in place. The flash is a separate ``flashView`` that the row lays over its whole fill.
///
/// Both views move only on the render server; the presenter adds no timers. The flash belongs to
/// the start of a skill or workflow, so the row never flashes for one that started earlier: not
/// when it starts showing a workspace (a new or reused row, or a sidebar that turns dark), and not
/// when it falls back to an older skill or workflow of another pane.
///
/// ```swift
/// let presenter = SidebarRowNameEffectPresenter(titleView: titleView, host: contentView)
/// row.addSubview(presenter.flashView, positioned: .below, relativeTo: contentView)
/// presenter.apply(
///     effect: .working,
///     isRenaming: false,
///     style: ShellXBonsplitStyles.titleEffectStyle(for: .dark),
///     rowIdentity: workspaceId
/// )
/// ```
@MainActor
final class SidebarRowNameEffectPresenter {
    /// Points between an `NSTextField`'s frame and its text on the left and the right.
    static let titleTextInset: CGFloat = 2

    /// The colors and timing of the row's effects, or `nil` in a light sidebar, where rows keep
    /// today's look and play no effect (ruling R6).
    ///
    /// - Parameter model: The row's model.
    static func style(for model: SidebarWorkspaceRowModel) -> TitleEffectStyle? {
        ShellXBonsplitStyles.titleEffectStyle(for: model.colorSchemeIsDark ? .dark : .light)
    }

    /// The effect the row's name plays: the snapshot's wherever the row has effect colors.
    ///
    /// - Parameter model: The row's model.
    /// - Returns: The effect, or `nil` when the name draws itself.
    static func shownEffect(for model: SidebarWorkspaceRowModel) -> AgentNameEffect? {
        Self.style(for: model) == nil ? nil : model.snapshot.nameEffect
    }

    /// Whether the row keeps the space of the spinner and the "running" pill its effect hides.
    ///
    /// A wrapped name keeps it, so the name wraps the same way and the row keeps its height while
    /// an effect starts and ends. A one-line name takes the space back.
    ///
    /// - Parameter model: The row's model.
    static func keepsStatusSpace(for model: SidebarWorkspaceRowModel) -> Bool {
        model.settings.wrapsWorkspaceTitles
            && model.snapshot.compactStatusGlyph == nil
            && shownEffect(for: model) != nil
    }

    /// The status row that says what the agent behind the name's effect does, and what it says.
    ///
    /// - Parameter model: The row's model.
    /// - Returns: The key of that row (the agent's, from the snapshot), the activity text, the
    ///   glyph's kind and the effect colors, or `nil` when every row keeps its own status.
    static func activity(
        for model: SidebarWorkspaceRowModel
    ) -> (statusKey: String, text: String, kind: TabActivity.Kind, style: TitleEffectStyle)? {
        guard let effectStyle = Self.style(for: model),
              let effect = model.snapshot.nameEffect,
              let text = model.snapshot.agentActivityText,
              let statusKey = model.snapshot.agentActivityStatusKey
        else { return nil }
        return (statusKey, text, effect.tabActivityKind, effectStyle)
    }

    /// The colored name, laid over the field's text.
    let effectView: TitleEffectView

    /// The one-time wash over the whole row; the row places it above its fill and below its content.
    let flashView: ActivityFlashView

    /// Whether the effect draws the name now, and so the field's own text is clear.
    ///
    /// While it is false the row gives the field its resting color.
    var isDrawingName: Bool { !effectView.isHidden }

    /// Whether the effects may move: off for rows that are scrolled away or not presented.
    var isPresentationActive = true {
        didSet {
            effectView.isPresentationActive = isPresentationActive
            flashView.isPresentationActive = isPresentationActive && playsEffects
        }
    }

    private let titleView: NSTextField

    /// The workspace whose effects the row shows, or `nil` before the first and after reuse.
    private var flashRowIdentity: UUID?

    /// The newest skill or workflow generation the row has shown for ``flashRowIdentity``.
    private var shownGeneration: UInt64 = 0

    /// Whether the row had effect colors at the last ``apply(effect:isRenaming:style:rowIdentity:)``;
    /// a light sidebar plays nothing, so it shows no generation either.
    private var playsEffects = false

    /// Creates the effect views and lays the name effect over `titleView` in `host`.
    ///
    /// - Parameters:
    ///   - titleView: The session name; it must already be a subview of `host`.
    ///   - host: The view holding the name; the effect view joins it just above the name.
    ///   - environment: Where the views learn whether they can be seen and may move; tests pass their own.
    init(
        titleView: NSTextField,
        host: NSView,
        environment: any TitleEffectEnvironment = SystemTitleEffectEnvironment()
    ) {
        self.titleView = titleView
        effectView = TitleEffectView(environment: environment)
        flashView = ActivityFlashView(environment: environment)
        effectView.isHidden = true
        flashView.isPresentationActive = false
        host.addSubview(effectView, positioned: .above, relativeTo: titleView)
    }

    /// Shows `effect` on the name, or gives the name back to the field when there is none.
    ///
    /// Call it after the field has its text, font, line limit and opacity, which an effect copies.
    /// While an effect plays, the field's text is clear; afterwards ``isDrawingName`` is false and
    /// the row gives the field its color back. A skill or workflow newer than any this row has
    /// shown for the workspace flashes once, even while renaming; the name effect itself hides
    /// while renaming. Calling it again with the same values changes nothing.
    ///
    /// - Parameters:
    ///   - effect: The agent's effect, or `nil` for none.
    ///   - isRenaming: Whether the name is being renamed in place.
    ///   - style: The effects' colors and timing, or `nil` for a row that plays no effect (a light
    ///     sidebar): the name then draws itself whatever `effect` is, and nothing flashes.
    ///   - rowIdentity: The workspace the row shows. When the row starts showing a workspace's
    ///     effects, whatever that workspace already plays counts as shown.
    func apply(effect: AgentNameEffect?, isRenaming: Bool, style: TitleEffectStyle?, rowIdentity: UUID) {
        let kind = style == nil ? nil : effect?.tabActivityKind
        let generation = style == nil ? nil : effect?.highlightGeneration
        markShownGenerations(generation, rowIdentity: rowIdentity, playsEffects: style != nil)
        let nameKind = isRenaming ? nil : kind
        if let style {
            flashView.configure(kind: kind, generation: generation ?? 0, style: style)
            effectView.configure(
                text: NSAttributedString(
                    string: titleView.stringValue,
                    attributes: [.font: titleView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]
                ),
                maximumNumberOfLines: titleView.maximumNumberOfLines,
                kind: nameKind,
                style: style
            )
        }
        effectView.alphaValue = titleView.alphaValue
        effectView.isHidden = nameKind == nil
        if nameKind != nil, titleView.textColor != .clear {
            titleView.textColor = .clear
        }
        layout()
    }

    /// Forgets the workspace the row showed; call it when the row is reused.
    ///
    /// A reused row starts again from what its workspace plays when it is next configured, so a
    /// skill that started while the row was away does not flash late, even for the same workspace.
    func forgetRow() {
        flashRowIdentity = nil
    }

    /// Lays the name effect over the field's text; call it whenever the field moves.
    func layout() {
        // Not `insetBy`: a field narrower than the insets, or not laid out yet, would give a null rect.
        let field = titleView.frame
        effectView.frame = NSRect(
            x: field.minX + Self.titleTextInset,
            y: field.minY,
            width: max(0, field.width - 2 * Self.titleTextInset),
            height: field.height
        )
    }

    /// Tells the flash which skill or workflow generations already passed, before it is configured.
    ///
    /// When the row starts showing a workspace's effects (a new identity, a reused row, or the
    /// first update with effect colors after a light sidebar), the generation it shows started
    /// earlier. Later, any generation up to the newest the row has shown started earlier too, such
    /// as an older workflow the row falls back to when a newer skill pauses. Generations only grow,
    /// so a larger one is a new start and flashes. A row without effect colors keeps its flash
    /// paused, so a flash left waiting from a dark sidebar never plays in a light one.
    private func markShownGenerations(_ generation: UInt64?, rowIdentity: UUID, playsEffects: Bool) {
        if rowIdentity != flashRowIdentity || !self.playsEffects {
            flashRowIdentity = rowIdentity
            shownGeneration = 0
            // Changing the value cancels a flash still waiting for the window. Generations count
            // per workspace, so the new one can equal the old one: clear it first.
            flashView.flashedGeneration = nil
            flashView.flashedGeneration = generation
        } else if let generation, generation <= shownGeneration {
            flashView.flashedGeneration = generation
        }
        if let generation {
            shownGeneration = max(shownGeneration, generation)
        }
        self.playsEffects = playsEffects
        flashView.isPresentationActive = isPresentationActive && playsEffects
    }
}

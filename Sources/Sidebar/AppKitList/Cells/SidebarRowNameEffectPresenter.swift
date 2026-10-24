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
/// Both views move only on the render server; the presenter adds no timers. A row reused for
/// another workspace, or one that appears while a skill already runs, does not flash for a start
/// that already happened.
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

    /// The agent status line that says what the agent does while the name plays an effect.
    ///
    /// Only Claude Code reports skills and workflows, so only its line carries the activity.
    static let activityStatusKey = "claude_code"

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

    /// What the row's agent status line says, and how its glyph moves, while the name plays an effect.
    ///
    /// - Parameter model: The row's model.
    /// - Returns: The activity text, the glyph's kind and the effect colors, or `nil` when the line
    ///   keeps its own status.
    static func activity(
        for model: SidebarWorkspaceRowModel
    ) -> (text: String, kind: TabActivity.Kind, style: TitleEffectStyle)? {
        guard let effectStyle = Self.style(for: model),
              let effect = model.snapshot.nameEffect,
              let text = model.snapshot.agentActivityText
        else { return nil }
        return (text, Self.kind(of: effect), effectStyle)
    }

    /// The Bonsplit effect that draws an agent name effect.
    ///
    /// - Parameter effect: The agent's effect.
    /// - Returns: ``TabActivity/Kind/working`` while the agent works, ``TabActivity/Kind/highlight``
    ///   for a skill or a workflow.
    static func kind(of effect: AgentNameEffect) -> TabActivity.Kind {
        switch effect {
        case .working:
            return .working
        case .skill, .workflow:
            return .highlight
        }
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
            flashView.isPresentationActive = isPresentationActive
        }
    }

    private let titleView: NSTextField

    /// The row the flash last showed, so a reused row starts from its new workspace's generation.
    private var flashRowIdentity: UUID?

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
        host.addSubview(effectView, positioned: .above, relativeTo: titleView)
    }

    /// Shows `effect` on the name, or gives the name back to the field when there is none.
    ///
    /// Call it after the field has its text, font, line limit and opacity, which an effect copies.
    /// While an effect plays, the field's text is clear; afterwards ``isDrawingName`` is false and
    /// the row gives the field its color back. A skill or workflow whose generation
    /// this row has not shown flashes once, even while renaming; the name effect itself hides while
    /// renaming. Calling it again with the same values changes nothing.
    ///
    /// - Parameters:
    ///   - effect: The agent's effect, or `nil` for none.
    ///   - isRenaming: Whether the name is being renamed in place.
    ///   - style: The effects' colors and timing, or `nil` for a row that plays no effect (a light
    ///     sidebar): the name then draws itself whatever `effect` is.
    ///   - rowIdentity: The workspace the row shows. When it changes, the flash takes the new
    ///     workspace's current generation as already shown.
    func apply(effect: AgentNameEffect?, isRenaming: Bool, style: TitleEffectStyle?, rowIdentity: UUID) {
        var kind: TabActivity.Kind?
        var generation: UInt64?
        if let effect, style != nil {
            kind = Self.kind(of: effect)
            generation = Self.highlightGeneration(of: effect)
        }
        if rowIdentity != flashRowIdentity {
            flashRowIdentity = rowIdentity
            flashView.flashedGeneration = generation
        }
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

    /// The generation of a skill or workflow, the only effects that flash.
    private static func highlightGeneration(of effect: AgentNameEffect) -> UInt64? {
        switch effect {
        case .working:
            return nil
        case .skill(_, let generation), .workflow(_, let generation):
            return generation
        }
    }
}

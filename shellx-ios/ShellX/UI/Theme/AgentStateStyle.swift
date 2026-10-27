import Foundation
import ShellXAppCore
import SwiftUI

/// How a live session's state looks in the agent strip: the dot colour and the words next to it.
/// The words always carry the state, so the colour is never the only cue. A state this app does
/// not know shows neither (PROTOCOL.md: no state badge).
struct AgentStateStyle: Equatable {
    let text: String?
    /// An asset catalog colour (darker in light mode, the soft tone in dark mode).
    let colorName: String?

    var color: Color? { colorName.map { Color($0) } }

    init(_ row: AgentStatusRow) {
        guard row.online else {
            // The last known state of a Mac that is not online: grey, and it says so (the row
            // already names the Mac).
            text = String(localized: "agent.state.offline")
            colorName = "StatusIdle"
            return
        }
        switch row.state {
        case .needsInput:
            text = String(localized: "agent.state.needsYou")
            colorName = "StatusNeedsYou"
        case .working:
            text = row.elapsed.map { String(localized: "agent.state.running \(Self.elapsedText($0))") }
                ?? String(localized: "agent.state.running")
            colorName = "StatusRunning"
        case .idle:
            text = String(localized: "agent.state.done")
            colorName = "StatusDone"
        case .ended:
            text = nil
            colorName = "StatusIdle"
        case .other:
            text = nil
            colorName = nil
        }
    }

    /// "4 minutes", "1 hour, 5 minutes", or seconds under a minute, in the app's language (not the
    /// region's), so the words match the sentence around them.
    static func elapsedText(_ elapsed: Duration, locale: Locale = appLocale) -> String {
        if elapsed < .seconds(60) {
            return elapsed.formatted(.units(allowed: [.seconds], width: .wide).locale(locale))
        }
        return elapsed.formatted(
            .units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2, fractionalPart: .hide(rounded: .down))
                .locale(locale))
    }

    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

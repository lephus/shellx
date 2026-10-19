import CmuxCommandPalette
import AppKit
import CMUXMobileCore
import Foundation
import ShellXBrand

extension ContentView {
    static let commandPaletteProUpgradeCommandId = "palette.pro.upgrade"
    static let commandPaletteProWelcomeChecklistCommandId = "palette.pro.welcomeChecklist"

    /// Encodes an upgrade offer for ``CommandPaletteContextKeys/accountUpgradeOffer``.
    /// No offer is written as `none`, so it stays distinct from a context
    /// that has not been filled in yet.
    nonisolated static func commandPaletteUpgradeOfferValue(_ tier: CmuxPlanTier?) -> String {
        switch tier {
        case .max: "max"
        case nil: "none"
        case .free, .go, .pro: "pro"
        }
    }

    /// Decodes ``CommandPaletteContextKeys/accountUpgradeOffer``; nil hides the
    /// command. A context without the key (before the account is known) offers
    /// Pro, as a signed-out account does.
    nonisolated static func commandPaletteUpgradeOffer(_ context: CommandPaletteContextSnapshot) -> CmuxPlanTier? {
        switch context.string(CommandPaletteContextKeys.accountUpgradeOffer) {
        case "max": .max
        case "none": nil
        default: .pro
        }
    }

    static func commandPaletteProCommandContributions() -> [CommandPaletteCommandContribution] {
        // ShellX: no upgrade or Pro commands (billing is a Manaflow service).
        guard ShellXFeatures.cloud else { return [] }
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        return [
            CommandPaletteCommandContribution(
                commandId: commandPaletteProWelcomeChecklistCommandId,
                title: constant(String(localized: "command.pro.welcomeChecklist.title", defaultValue: "Welcome to cmux Pro")),
                subtitle: constant(String(localized: "command.auth.subtitle", defaultValue: "Account")),
                keywords: ["pro", "welcome", "checklist", "onboarding", "cloud", "billing", "ios", "provider"]
            ),
            CommandPaletteCommandContribution(
                commandId: commandPaletteProUpgradeCommandId,
                title: { context in
                    ProUpgradePresenter.upgradeCommandTitle(for: commandPaletteUpgradeOffer(context) ?? .pro)
                },
                subtitle: constant(String(localized: "command.auth.subtitle", defaultValue: "Account")),
                keywords: ["pro", "max", "upgrade", "subscription", "billing", "plan", "pricing", "cloud", "purchase", "buy"],
                when: { context in commandPaletteUpgradeOffer(context) != nil }
            ),
        ]
    }

    func registerProCommandHandlers(_ registry: inout CommandPaletteHandlerRegistry) {
        guard ShellXFeatures.cloud else { return }
        registry.register(commandId: Self.commandPaletteProUpgradeCommandId) {
#if DEBUG
            cmuxDebugLog("palette.pro.upgrade.invoke")
#endif
            ProUpgradePresenter.present(source: .commandPalette)
        }
        registry.register(commandId: Self.commandPaletteProWelcomeChecklistCommandId) {
#if DEBUG
            cmuxDebugLog("palette.pro.welcomeChecklist.invoke")
#endif
            ProWelcomeChecklistPresenter.present()
        }
    }
}

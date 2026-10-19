import CMUXMobileCore
import CmuxCommandPalette
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Every upgrade entrypoint (account menu, sidebar help menu, Help menu,
/// command palette) offers the tier above the account's plan: Free and Go
/// see Pro, Pro sees Max, and Max sees nothing.
@MainActor
struct AccountUpgradeOfferTests {
    @Test func menuTitlesNameTheOfferedTier() {
        #expect(ProUpgradePresenter.upgradeMenuTitle(for: .pro) == String(
            localized: "menu.help.upgradeToPro", defaultValue: "Upgrade to cmux Pro…"
        ))
        #expect(ProUpgradePresenter.upgradeMenuTitle(for: .max) == String(
            localized: "menu.help.upgradeToMax", defaultValue: "Upgrade to cmux Max…"
        ))
    }

    /// ShellX: billing and Pro are Manaflow services, so no tier shows the
    /// footer upgrade badge and the palette offers no upgrade command.
    @Test func footerBadgeAndPaletteNeverOfferAnUpgrade() {
        for tier in CmuxPlanTier.allCases {
            #expect(!SidebarFooterPresentationPolicy.isUpgradeVisible(isProActive: tier.includesPro), "\(tier)")
        }
        #expect(ContentView.commandPaletteProCommandContributions().isEmpty)
    }
}

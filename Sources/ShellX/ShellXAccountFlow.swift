import AppKit
import CmuxSettingsUI
import Observation
import ShellXRemoteCore

/// ShellX: Settings → Account's `AccountFlow`, backed by the ShellX account (`ShellXAccount`, email and
/// password against the ShellX API) instead of the Manaflow sign-in in `HostAccountFlow`, which stays off.
/// No teams, billing or Pro: those rows stay hidden.
@MainActor
@Observable
final class ShellXAccountFlow: AccountFlow {
    static let shared = ShellXAccountFlow(account: ShellXAccount(service: .shared))

    @ObservationIgnored private let account: ShellXAccount

    init(account: ShellXAccount) {
        self.account = account
    }

    var currentIdentity: AccountIdentity? {
        account.identity.map { AccountIdentity(id: $0.userID, displayName: "", email: $0.email) }
    }

    var isWorkingOnAuth: Bool { account.isWorking }

    /// Opens the "Sign in to ShellX" sheet; it closes itself once the server accepts the password.
    func startSignIn() {
        let account = account
        SignInSheetPresenter.shared.present { email, password in
            try await account.signIn(email: email, password: password)
        }
    }

    func signOut() async {
        await account.signOut()
    }

    var availableTeams: [AccountTeamSummary] { [] }
    var selectedTeamID: String? { nil }
    func selectTeam(id: String?) async throws {}
    var signInIsSlow: Bool { false }
    func openSignInInDefaultBrowser() {}
    func refreshCurrentUser() async {}
    func openProUpgrade() {}
    func refreshBillingPlan() async {}
    func openBillingPortal() {}
    var isProUpgradeAvailable: Bool { false }
    var isProActive: Bool { false }
    var canManageBilling: Bool { false }
}

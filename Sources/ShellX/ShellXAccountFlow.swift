import AppKit
import CmuxSettingsUI
import SwiftUI
import Observation
import ShellXBrand
import ShellXRemoteCore
import ShellXRemoteUI

/// ShellX: Settings → Account's `AccountFlow`, backed by the ShellX account (`ShellXAccount`, Google sign-in
/// against the ShellX API) instead of the Manaflow sign-in in `HostAccountFlow`, which stays off.
/// No teams, billing or Pro: those rows stay hidden.
@MainActor
@Observable
final class ShellXAccountFlow: AccountFlow {
    static let shared = ShellXAccountFlow(account: ShellXAccount(service: .shared, openURL: { NSWorkspace.shared.open($0) }))

    @ObservationIgnored private let account: ShellXAccount

    init(account: ShellXAccount) {
        self.account = account
    }

    var currentIdentity: AccountIdentity? {
        account.identity.map { identity in
            AccountIdentity(
                id: identity.userID,
                displayName: "",
                email: identity.email,
                detail: identity.signedInAt.map(Self.lastSignInText)
            )
        }
    }

    private static func lastSignInText(_ date: Date) -> String {
        String(
            format: String(localized: "settings.account.lastSignIn", defaultValue: "Last signed in %@"),
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    var isWorkingOnAuth: Bool { account.isWorking }

    /// Opens the "Sign in to ShellX" sheet with the Google button; it closes once the person confirms.
    func startSignIn() {
        presentGoogleSheet(.signIn)
    }

    /// Opens the "Switch to Google sign-in" sheet for a password session.
    func startGoogleSwitch() {
        presentGoogleSheet(.link)
    }

    /// At launch: a session the server ended shows the sign-in sheet; the core's session fills in the email and
    /// method; a password account is offered the switch to Google once.
    func prepareAtLaunch(defaults: UserDefaults) {
        account.onSignedOutByServer = { [weak self] in self?.startSignIn() }
        let account = account
        Task { @MainActor [weak self] in
            await account.reconcileWithSession()
            if account.takeGoogleSwitchOffer(defaults: defaults) { self?.startGoogleSwitch() }
        }
    }

    private func presentGoogleSheet(_ purpose: GoogleSignInPurpose) {
        let account = account
        let model = GoogleSignInModel(
            purpose: purpose, labels: .localized,
            signIn: { try await account.signInWithGoogle(purpose: purpose).email },
            cancel: { await account.cancelGoogleSignIn() }
        )
        SignInSheetPresenter.shared.present(model: model)
    }

    func signOut() async {
        await account.signOut()
    }

    /// Sign-in methods, the Google switch and the delete link; hidden while signed out.
    var accountDetailContent: AnyView? {
        guard account.identity != nil else { return nil }
        return AnyView(ShellXAccountDetailView(
            account: account,
            onSwitchToGoogle: { [weak self] in self?.startGoogleSwitch() },
            openURL: { NSWorkspace.shared.open($0) }
        ))
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

import ShellXAppCore

/// What Settings › Account and the home's banner can do for the signed-in account; nil in the demo.
struct AccountActions {
    var authMethod: AccountAuthMethod
    var signOut: () async -> Void
    var switchToGoogle: () async throws -> Void
    var deleteAccount: () async throws -> Void
    /// A new model for the deletion sheet of an email session (it mails the code, then deletes with it); nil in fakes
    /// that have none.
    var deleteCode: (@MainActor () -> EmailSignInModel)? = nil
}

extension AccountActions {
    /// `authMethod` is `coordinator.authMethod ?? .google`.
    @MainActor init(coordinator: AppCoordinator) {
        self.init(
            authMethod: coordinator.authMethod ?? .google,
            signOut: { await coordinator.signOut() },
            switchToGoogle: { try await coordinator.switchToGoogle() },
            deleteAccount: { try await coordinator.deleteAccount() },
            deleteCode: { coordinator.makeDeleteAccountCode() })
    }
}

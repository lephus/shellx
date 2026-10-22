import Foundation
import Testing
@testable import ShellXRemoteCore

// MARK: - Sign-in with the remote-machines gate off (Settings → Account)

@MainActor @Test func accountSignInWorksWithTheGateOff() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service)
    #expect(account.identity == nil)

    try await account.signIn(email: "dev@shellx.test", password: "pw")
    #expect(rig.core.methods == ["config.set", "auth.login"])
    #expect(rig.core.lastParams("auth.login") == ["email": .string("dev@shellx.test"), "password": .string("pw")])
    #expect(account.identity == ShellXAccount.Identity(userID: "u_1", email: "dev@shellx.test"))
    // Only the account: no host, bridge or remote session starts.
    #expect(rig.launcher.calls.isEmpty)
    #expect(rig.bridge.starts.get().isEmpty)
    #expect(!rig.service.isSignedIn)
}

@MainActor @Test func accountSignInFailureKeepsSignedOut() async {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service)
    let thrown = await errorCode { try await account.signIn(email: "dev@shellx.test", password: "wrong") }
    #expect(thrown == "invalid_credentials")
    #expect(account.identity == nil)
    #expect(ShellXAccount(service: rig.service).identity == nil)
}

@MainActor @Test func accountIdentitySurvivesRelaunch() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    try await ShellXAccount(service: rig.service).signIn(email: "dev@shellx.test", password: "pw")
    let relaunched = ShellXAccount(service: rig.service)
    #expect(relaunched.identity == ShellXAccount.Identity(userID: "u_1", email: "dev@shellx.test"))
}

@MainActor @Test func accountSignOutLogsOutEvenAfterRelaunch() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    try await ShellXAccount(service: rig.service).signIn(email: "dev@shellx.test", password: "pw")
    // A new app run: a new service on the same state, whose core was never configured.
    let relaunched = ShellXRemoteService(environment: rig.service.env)
    let account = ShellXAccount(service: relaunched)
    #expect(account.identity != nil)
    let before = rig.core.calls.count

    await account.signOut()
    #expect(Array(rig.core.methods.dropFirst(before)) == ["config.set", "auth.logout"])
    #expect(account.identity == nil)
    #expect(!account.isWorking)
    #expect(ShellXAccount(service: relaunched).identity == nil)
}

// MARK: - With the gate on, the remote service owns the session

@MainActor @Test func accountSignInWithTheGateOnStartsTheRemoteSession() async throws {
    let rig = ServiceRig(signedIn: false)
    let account = ShellXAccount(service: rig.service)
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    #expect(account.identity == ShellXAccount.Identity(userID: "u_1", email: "dev@shellx.test"))
    #expect(rig.service.isSignedIn)
    #expect(await until { rig.service.hostState == rig.hostConnected })

    await account.signOut()
    #expect(rig.core.methods.last == "auth.logout")
    #expect(!rig.service.isSignedIn)
    #expect(account.identity == nil)
}

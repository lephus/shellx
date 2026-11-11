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
    #expect(account.identity?.userID == "u_1")
    #expect(account.identity?.email == "dev@shellx.test")
    #expect(account.identity?.signedInAt != nil)
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
    let account = ShellXAccount(service: rig.service)
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    let relaunched = ShellXAccount(service: rig.service)
    #expect(relaunched.identity == account.identity)
    #expect(relaunched.identity?.signedInAt != nil)
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
    #expect(account.identity?.userID == "u_1")
    #expect(account.identity?.email == "dev@shellx.test")
    #expect(rig.service.isSignedIn)
    #expect(await until { rig.service.hostState == rig.hostConnected })

    await account.signOut()
    #expect(rig.core.methods.last == "auth.logout")
    #expect(!rig.service.isSignedIn)
    #expect(account.identity == nil)
}

// MARK: - Google sign-in, switching, sign-in methods, server sign-out

@MainActor private final class Opened { var urls: [URL] = [] }

@MainActor private func googleAccount(_ rig: ServiceRig, _ opened: Opened) -> ShellXAccount {
    ShellXAccount(service: rig.service, openURL: { opened.urls.append($0); return true })
}

@MainActor @Test func googleSignInOpensTheBrowserAndSavesTheGoogleIdentity() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let opened = Opened()
    let account = googleAccount(rig, opened)
    let identity = try await account.signInWithGoogle(purpose: .signIn)
    #expect(rig.core.methods == ["config.set", "auth.google.begin", "auth.google.finish"])
    #expect(opened.urls.map(\.absoluteString) == ["https://accounts.google.com/o/oauth2/v2/auth?client_id=test"])
    #expect(identity.email == "g@shellx.test")
    #expect(account.identity?.email == "g@shellx.test")
    #expect(account.identity?.authMethod == "google")
    #expect(account.identity?.usesPassword == false)
    #expect(account.googleStep == .idle)
    #expect(ShellXAccount(service: rig.service).identity == account.identity)
}

@MainActor @Test func googleSignInWithTheGateOnStartsTheSession() async throws {
    let rig = ServiceRig(signedIn: false)
    let account = googleAccount(rig, Opened())
    _ = try await account.signInWithGoogle(purpose: .signIn)
    #expect(rig.service.isSignedIn)
    #expect(await until { rig.service.hostState == rig.hostConnected })
}

@MainActor @Test func googleSignInFailsWhenTheBrowserCannotOpen() async {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service, openURL: { _ in false })
    let thrown = await errorCode { _ = try await account.signInWithGoogle(purpose: .signIn) }
    #expect(thrown == "browser_unavailable")
    #expect(rig.core.lastParams("auth.google.cancel") == ["flow_id": .string("flow-1")])
    #expect(account.identity == nil)
    #expect(account.googleStep == .idle)
}

@MainActor @Test func cancelGoogleSignInCancelsTheWaitingFlow() async {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = googleAccount(rig, Opened())
    rig.core.holdNext.with { $0 = "auth.google.finish" }
    rig.core.failures.with { $0["auth.google.finish"] = ["google_cancelled"] }
    let task = Task { await errorCode { _ = try await account.signInWithGoogle(purpose: .signIn) } }
    #expect(await until { rig.core.isHoldingCall })
    #expect(account.googleStep == .waiting(.signIn))
    await account.cancelGoogleSignIn()
    #expect(rig.core.lastParams("auth.google.cancel") == ["flow_id": .string("flow-1")])
    rig.core.releaseHeldCall()
    #expect(await task.value == "google_cancelled")
    #expect(account.googleStep == .idle)
    #expect(account.identity == nil)
}

@MainActor @Test func switchToGoogleKeepsTheSessionAndUpdatesTheIdentity() async throws {
    let rig = ServiceRig(signedIn: false)
    let opened = Opened()
    let account = googleAccount(rig, opened)
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    let registers = rig.core.count("machines.register")
    _ = try await account.signInWithGoogle(purpose: .link)
    #expect(rig.core.lastParams("auth.google.begin") == ["purpose": .string("link")])
    #expect(rig.core.count("machines.register") == registers)
    #expect(account.identity?.authMethod == "google")
    #expect(account.identity?.email == "g@shellx.test")
    #expect(rig.core.count("account.identities.list") >= 1)
}

@MainActor @Test func oldAccountRecordsReadAsPassword() throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let file = ShellXAccount.recordFile(stateRoot: rig.service.env.paths.stateRoot)
    try OwnerOnlyFile.ensurePrivateDirectory(file.deletingLastPathComponent())
    try OwnerOnlyFile.write(Data(#"{"userID":"u_1","email":"old@shellx.test"}"#.utf8), to: file)
    let account = ShellXAccount(service: rig.service)
    #expect(account.identity?.authMethod == nil)
    #expect(account.identity?.usesPassword == true)
}

@MainActor @Test func googleSwitchIsOfferedOnceForAPasswordAccount() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = googleAccount(rig, Opened())
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    #expect(account.takeGoogleSwitchOffer(defaults: defaults))
    #expect(!account.takeGoogleSwitchOffer(defaults: defaults))
    _ = try await account.signInWithGoogle(purpose: .link)
    let fresh = UserDefaults(suiteName: UUID().uuidString)!
    #expect(!account.takeGoogleSwitchOffer(defaults: fresh))
}

@MainActor @Test func signInMethodsListAndRemoveAnAppleID() async {
    let rig = ServiceRig(gate: false, signedIn: true)
    rig.core.identities.with {
        $0 = [.object(["identity_id": .string("g1"), "provider": .string("google"), "email": .string("g@shellx.test"),
                       "is_private_email": .bool(false), "linked_via_device_name": .null, "created_at_unix": .number(1)]),
              .object(["identity_id": .string("a1"), "provider": .string("apple"), "email": .string("x@privaterelay.appleid.com"),
                       "is_private_email": .bool(true), "linked_via_device_name": .string("Phu's iPhone"), "created_at_unix": .number(2)])]
    }
    let account = googleAccount(rig, Opened())
    await account.refreshSignInMethods()
    #expect(account.signInMethods.map(\.id) == ["g1", "a1"])
    rig.core.holdNext.with { $0 = "account.identities.remove" }
    let task = Task { await account.removeSignInMethod(id: "a1") }
    #expect(await until { rig.core.isHoldingCall })
    #expect(account.removingSignInMethodIDs.contains("a1"))
    rig.core.releaseHeldCall()
    await task.value
    #expect(account.signInMethods.map(\.id) == ["g1"])
    #expect(account.removingSignInMethodIDs.isEmpty)
}

@MainActor @Test func aFailedListKeepsTheLastListAndShowsTheCode() async {
    let rig = ServiceRig(gate: false, signedIn: true)
    rig.core.identities.with {
        $0 = [.object(["identity_id": .string("g1"), "provider": .string("google"), "email": .string("g@shellx.test"),
                       "is_private_email": .bool(false), "linked_via_device_name": .null, "created_at_unix": .number(1)])]
    }
    let account = googleAccount(rig, Opened())
    await account.refreshSignInMethods()
    #expect(account.signInMethodsErrorCode == nil)
    rig.core.down.with { $0["account.identities.list"] = "network" }
    await account.refreshSignInMethods()
    #expect(account.signInMethods.map(\.id) == ["g1"])
    #expect(account.signInMethodsErrorCode == "network")
}

@MainActor @Test func serverSignOutForgetsTheIdentityAndAsksForSignIn() async throws {
    let rig = ServiceRig(signedIn: false)
    let account = googleAccount(rig, Opened())
    var calls = 0
    account.onSignedOutByServer = { calls += 1 }
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    #expect(await until { rig.service.hostState == rig.hostConnected })
    let file = ShellXAccount.recordFile(stateRoot: rig.service.env.paths.stateRoot)
    #expect(FileManager.default.fileExists(atPath: file.path))
    rig.core.down.with { $0["machines.list"] = "unauthorized" }
    _ = await rig.advance(ShellXRemoteService.machinesInterval, waitingFor: "machines.list")
    #expect(await until { account.identity == nil })
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(calls == 1)
}

@MainActor @Test func reconcileTakesEmailAndMethodFromTheCoreSession() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = googleAccount(rig, Opened())
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    rig.core.sessionEmail.with { $0 = "new@shellx.test" }
    rig.core.sessionAuthMethod.with { $0 = "google" }
    await account.reconcileWithSession()
    #expect(account.identity?.email == "new@shellx.test")
    #expect(account.identity?.authMethod == "google")
    #expect(ShellXAccount(service: rig.service).identity == account.identity)
}

@MainActor @Test func reconcileWithoutASessionForgetsTheIdentityAndAsksForSignIn() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = googleAccount(rig, Opened())
    var calls = 0
    account.onSignedOutByServer = { calls += 1 }
    try await account.signIn(email: "dev@shellx.test", password: "pw")
    rig.core.down.with { $0["auth.session"] = "io" }
    await account.reconcileWithSession()
    #expect(account.identity != nil)
    rig.core.down.with { $0["auth.session"] = nil }
    rig.core.signedIn.with { $0 = false }
    await account.reconcileWithSession()
    #expect(account.identity == nil)
    let file = ShellXAccount.recordFile(stateRoot: rig.service.env.paths.stateRoot)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(calls == 1)
}

// MARK: - Email code sign-in

@MainActor @Test func emailCodeRequestConfiguresTheCoreAndChangesNoSession() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service)
    let challenge = try await account.requestEmailCode(email: "Foo@Bar.com", locale: "vi")
    #expect(challenge.email == "foo@bar.com")
    #expect(rig.core.methods == ["config.set", "auth.email.begin"])
    #expect(rig.core.lastParams("auth.email.begin") == ["email": .string("Foo@Bar.com"), "locale": .string("vi")])
    #expect(account.identity == nil)
}

@MainActor @Test func emailCodeSignsInAndSavesTheEmailIdentity() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service)
    let challenge = try await account.requestEmailCode(email: "Foo@Bar.com", locale: "vi")
    let identity = try await account.signInWithEmailCode(challengeID: challenge.challengeID, code: "004217")
    #expect(identity.email == "foo@bar.com")
    #expect(identity.authMethod == "email")
    #expect(identity.usesPassword == false)
    #expect(identity.signedInAt != nil)
    #expect(account.identity == identity)
    #expect(ShellXAccount(service: rig.service).identity == account.identity)
    // Only the account: no host, bridge or remote session starts.
    #expect(rig.launcher.calls.isEmpty)
    #expect(!rig.service.isSignedIn)
}

@MainActor @Test func emailCodeSignInWithTheGateOnStartsTheSession() async throws {
    let rig = ServiceRig(signedIn: false)
    let account = ShellXAccount(service: rig.service)
    let challenge = try await account.requestEmailCode(email: "Foo@Bar.com", locale: "en")
    try await account.signInWithEmailCode(challengeID: challenge.challengeID, code: "004217")
    #expect(rig.service.isSignedIn)
    #expect(await until { rig.service.hostState == rig.hostConnected })
}

@MainActor @Test func aWrongEmailCodeKeepsSignedOutAndCanBeRetried() async throws {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = ShellXAccount(service: rig.service)
    let challenge = try await account.requestEmailCode(email: "Foo@Bar.com", locale: "en")
    let thrown = await errorCode { _ = try await account.signInWithEmailCode(challengeID: challenge.challengeID, code: "000000") }
    #expect(thrown == "invalid_code")
    #expect(account.identity == nil)
    #expect(ShellXAccount(service: rig.service).identity == nil)
    try await account.signInWithEmailCode(challengeID: challenge.challengeID, code: "004217")
    #expect(account.identity?.authMethod == "email")
}

@MainActor @Test func emailCodeSignInIsRefusedWhileGoogleWaits() async {
    let rig = ServiceRig(gate: false, signedIn: false)
    let account = googleAccount(rig, Opened())
    rig.core.holdNext.with { $0 = "auth.google.finish" }
    rig.core.failures.with { $0["auth.google.finish"] = ["google_cancelled"] }
    let task = Task { await errorCode { _ = try await account.signInWithGoogle(purpose: .signIn) } }
    #expect(await until { rig.core.isHoldingCall })
    #expect(account.googleStep == .waiting(.signIn))
    let thrown = await errorCode { _ = try await account.signInWithEmailCode(challengeID: "ch-1", code: "004217") }
    #expect(thrown == "google_in_progress")
    #expect(rig.core.count("auth.email.finish") == 0)
    await account.cancelGoogleSignIn()
    rig.core.releaseHeldCall()
    #expect(await task.value == "google_cancelled")
    #expect(account.identity == nil)
}

@MainActor @Test func cancelBeforeBeginAnswersEndsTheFlowWithoutOpeningTheBrowser() async {
    let rig = ServiceRig(gate: false, signedIn: false)
    let opened = Opened()
    let account = googleAccount(rig, opened)
    rig.core.holdNext.with { $0 = "auth.google.begin" }
    let first = Task { await errorCode { _ = try await account.signInWithGoogle(purpose: .signIn) } }
    #expect(await until { rig.core.isHoldingCall })
    #expect(account.googleStep == .waiting(.signIn))
    // A second click while begin is still in flight is refused.
    let second = await errorCode { _ = try await account.signInWithGoogle(purpose: .signIn) }
    #expect(second == "google_in_progress")
    await account.cancelGoogleSignIn()
    rig.core.releaseHeldCall()
    #expect(await first.value == "google_cancelled")
    #expect(opened.urls.isEmpty)
    #expect(rig.core.lastParams("auth.google.cancel") == ["flow_id": .string("flow-1")])
    #expect(rig.core.count("auth.google.finish") == 0)
    #expect(account.googleStep == .idle)
    #expect(account.identity == nil)
}

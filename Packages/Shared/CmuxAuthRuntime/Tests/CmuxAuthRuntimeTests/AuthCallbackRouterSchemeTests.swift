import Foundation
import Testing
@testable import CmuxAuthRuntime

/// ShellX registers the `shellx` scheme family (Resources/Info.plist via
/// `CMUX_AUTH_CALLBACK_SCHEME`) and must never answer cmux's, which an installed
/// cmux owns.
@Suite struct AuthCallbackRouterSchemeTests {
    @Test(arguments: ["shellx", "shellx-nightly", "shellx-rc", "shellx-dev"])
    func acceptsTheShellXSchemes(_ scheme: String) throws {
        let url = try #require(URL(string: "\(scheme)://auth-callback?stack_refresh=r&stack_access=a"))
        #expect(AuthCallbackRouter().isAuthCallbackURL(url))
    }

    @Test(arguments: ["cmux", "cmux-nightly", "cmux-rc", "cmux-dev"])
    func rejectsTheCmuxSchemes(_ scheme: String) throws {
        let url = try #require(URL(string: "\(scheme)://auth-callback?stack_refresh=r&stack_access=a"))
        #expect(!AuthCallbackRouter().isAuthCallbackURL(url))
    }

    @Test func honorsTheTaggedBuildsOwnScheme() throws {
        let url = try #require(URL(string: "shellx-dev-my-tag://auth-callback?stack_refresh=r&stack_access=a"))
        #expect(!AuthCallbackRouter().isAuthCallbackURL(url))
        #expect(AuthCallbackRouter(extraAllowedScheme: "shellx-dev-my-tag").isAuthCallbackURL(url))
    }
}

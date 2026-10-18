import Testing
import Foundation
@testable import ShellXBrand

@Suite struct ShellXNetworkPolicyTests {
    @Test func forbiddenHostsMatchSpec() {
        #expect(ShellXNetworkPolicy.forbiddenHosts == [
            "cmux.com",
            "cmux.dev",
            "manaflow",
            "stack-auth.com",
            "sentry.io",
            "posthog.com",
            "axiom.co",
            "coderouter.dev",
            "workers.dev",
            "relay.cmux.dev",
        ])
    }

    @Test func shellXHostsAreNotForbidden() {
        #expect(!ShellXNetworkPolicy.isForbidden(host: "shellx.pro"))
        #expect(!ShellXNetworkPolicy.isForbidden(host: "download.shellx.pro"))
        #expect(!ShellXNetworkPolicy.isForbidden(host: ShellXBrand.websiteURL.host ?? ""))
        #expect(!ShellXNetworkPolicy.isForbidden(host: ShellXBrand.updateFeedURL.host ?? ""))
    }

    @Test func upstreamHostsAreForbidden() {
        #expect(ShellXNetworkPolicy.isForbidden(host: "cmux.com"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "files.cmux.com"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "presence.cmux.dev"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "o4507547940749312.ingest.us.sentry.io"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "us.i.posthog.com"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "cmux-v2.debussy.workers.dev"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "API.Stack-Auth.com"))
        #expect(ShellXNetworkPolicy.isForbidden(host: "manaflow.ai"))
        #expect(ShellXNetworkPolicy.isForbidden(url: URL(string: "https://github.com/manaflow-ai/cmux")!))
        #expect(!ShellXNetworkPolicy.isForbidden(url: ShellXBrand.sourceCodeURL))
    }

    @Test func lookalikeHostsAreNotForbidden() {
        #expect(!ShellXNetworkPolicy.isForbidden(host: "notcmux.com"))
        #expect(!ShellXNetworkPolicy.isForbidden(host: "cmux.community"))
    }
}

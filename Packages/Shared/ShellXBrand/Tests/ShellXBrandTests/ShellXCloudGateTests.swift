import Testing
@testable import ShellXBrand

@Suite struct ShellXCloudGateTests {
    @Test func cloudIsHardOffAndIndependentOfRemoteMachines() {
        #expect(ShellXFeatures.cloud == false)
        #expect(ShellXFeatures.codeRouter == false)
        #expect(ShellXFeatures.remoteMachines == false)
    }

    @Test func cloudSocketMethodsAreRefused() {
        for method in [
            "auth.status", "auth.sign_in_url", "auth.begin_sign_in", "auth.sign_out",
            "auth.team.list", "auth.team.use", "auth.team.invite",
            "vm.list", "vm.create", "vm.billing_checkout", "vm.tunnel_up", "vm.feature_status",
            "remotes.list", "remotes.add", "aiAccounts.list", "aiAccounts.upload",
            "billing.checkout",
        ] {
            #expect(ShellXCloudGate.unavailableService(forSocketMethod: method) == .cloud, "\(method)")
        }
    }

    @Test func codeRouterSocketMethodsAreRefusedAsCodeRouter() {
        for method in [
            "coderouter.handoff.arm", "coderouter.handoff.complete",
            "coderouter.machines", "coderouter.claude_upstream.get",
        ] {
            #expect(ShellXCloudGate.unavailableService(forSocketMethod: method) == .codeRouter, "\(method)")
        }
    }

    /// `auth.login` is the local socket password handshake, not Stack Auth.
    @Test func localSocketMethodsStayOpen() {
        for method in [
            "auth.login", "system.ping", "workspace.list", "surface.send_text",
            "authx.status", "vmx.list", "remote.status", "feedback.submit",
        ] {
            #expect(ShellXCloudGate.unavailableService(forSocketMethod: method) == nil, "\(method)")
        }
    }

    @Test func cloudCLICommandsAreRefused() {
        for command in [
            "auth", "login", "logout", "billing", "vm", "cloud", "vpn",
            "remotes", "remote", "ai-accounts",
            "vm-pty-attach", "vm-tui-connect", "vm-ssh-attach", "VM",
        ] {
            #expect(ShellXCloudGate.unavailableService(forCLICommand: command) == .cloud, "\(command)")
        }
        #expect(ShellXCloudGate.unavailableService(forCLICommand: "coderouter") == .codeRouter)
        #expect(ShellXCloudGate.unavailableService(forCLICommand: "cr") == .codeRouter)
    }

    @Test func localCLICommandsStayOpen() {
        for command in ["ping", "list-workspaces", "agent", "mobile", "ssh", "browser", "notify", "feedback"] {
            #expect(ShellXCloudGate.unavailableService(forCLICommand: command) == nil, "\(command)")
        }
    }
}

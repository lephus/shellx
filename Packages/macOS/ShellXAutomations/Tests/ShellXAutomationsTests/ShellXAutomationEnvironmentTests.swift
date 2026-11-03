import Foundation
import Testing
@testable import ShellXAutomations

@Suite struct ShellXAutomationEnvironmentTests {
    private let home = URL(filePath: "/tmp/shellx-env-home", directoryHint: .isDirectory)

    @Test func releaseAndDevRoots() {
        let release = ShellXAutomationEnvironment(bundleIdentifier: "pro.shellx.desktop", home: home, cliPath: "/cli", notifierAppPath: "/n.app")
        #expect(release.automationsRoot.path == "/tmp/shellx-env-home/.shellx/automations")
        #expect(release.labelPrefix == "pro.shellx.automation.")
        #expect(release.skillsRoot.path == "/tmp/shellx-env-home/.claude/skills")
        #expect(release.launchAgentsDirectory.path == "/tmp/shellx-env-home/Library/LaunchAgents")
        #expect(release.changeStampURL.path == "/tmp/shellx-env-home/.shellx/automations/.changed")

        let dev = ShellXAutomationEnvironment(bundleIdentifier: "pro.shellx.desktop.dev.foo", home: home, cliPath: "/cli", notifierAppPath: "/n.app")
        #expect(dev.automationsRoot.path == "/tmp/shellx-env-home/.shellx/automations-dev/pro.shellx.desktop.dev.foo")
        #expect(dev.labelPrefix == "pro.shellx.automation.dev.pro.shellx.desktop.dev.foo.")
        #expect(dev.skillsRoot == release.skillsRoot)
        #expect(dev.cliPath == "/cli" && dev.notifierAppPath == "/n.app")
    }
}

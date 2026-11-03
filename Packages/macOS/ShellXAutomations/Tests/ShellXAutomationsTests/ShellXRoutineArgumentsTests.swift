import Testing
@testable import ShellXAutomations

@Suite struct ShellXRoutineArgumentsTests {
    private func parse(_ args: [String]) throws(ShellXRoutineArgumentsError) -> ShellXRoutineCommand {
        try ShellXRoutineArguments(args).command
    }

    @Test func runDefaultsToManual() throws {
        #expect(try parse(["run", "abc"]) == .run(id: "abc", trigger: .manual))
    }

    @Test func runAcceptsScheduleTrigger() throws {
        #expect(try parse(["run", "abc", "--trigger", "schedule"]) == .run(id: "abc", trigger: .schedule))
        #expect(try parse(["run", "--trigger", "manual", "abc"]) == .run(id: "abc", trigger: .manual))
    }

    @Test func runRejectsBadInput() {
        #expect(throws: ShellXRoutineArgumentsError.missingID) { try parse(["run"]) }
        #expect(throws: ShellXRoutineArgumentsError.invalidTrigger("cron")) { try parse(["run", "abc", "--trigger", "cron"]) }
        #expect(throws: ShellXRoutineArgumentsError.missingValue(flag: "--trigger")) { try parse(["run", "abc", "--trigger"]) }
        #expect(throws: ShellXRoutineArgumentsError.unexpectedArgument("def")) { try parse(["run", "abc", "def"]) }
    }

    @Test func notifyParsesEveryField() throws {
        #expect(try parse(["notify", "--name", "digest", "--status", "needs-you", "--body", "Approve the deploy"])
            == .notify(name: "digest", status: .needsYou, body: "Approve the deploy"))
        #expect(try parse(["notify", "--status", "done", "--body", "", "--name", "digest"])
            == .notify(name: "digest", status: .done, body: ""))
        #expect(try parse(["notify", "--name", "digest", "--status", "failed", "--body", "boom"])
            == .notify(name: "digest", status: .failed, body: "boom"))
    }

    @Test func notifyRequiresStatus() {
        #expect(throws: ShellXRoutineArgumentsError.missingValue(flag: "--status")) {
            try parse(["notify", "--name", "digest", "--body", "hi"])
        }
    }

    @Test func notifyRejectsBadInput() {
        #expect(throws: ShellXRoutineArgumentsError.missingValue(flag: "--name")) { try parse(["notify", "--status", "done", "--body", "hi"]) }
        #expect(throws: ShellXRoutineArgumentsError.missingValue(flag: "--body")) { try parse(["notify", "--name", "a", "--status", "done"]) }
        #expect(throws: ShellXRoutineArgumentsError.invalidStatus("ok")) { try parse(["notify", "--name", "a", "--status", "ok", "--body", "hi"]) }
        #expect(throws: ShellXRoutineArgumentsError.unexpectedArgument("--sound")) { try parse(["notify", "--name", "a", "--status", "done", "--body", "hi", "--sound"]) }
    }

    @Test func listTakesOptionalJSON() throws {
        #expect(try parse(["list"]) == .list(json: false))
        #expect(try parse(["list", "--json"]) == .list(json: true))
        #expect(throws: ShellXRoutineArgumentsError.unexpectedArgument("x")) { try parse(["list", "x"]) }
    }

    @Test func unknownSubcommandIsAUsageError() {
        #expect(throws: ShellXRoutineArgumentsError.unknownSubcommand("start")) { try parse(["start", "abc"]) }
        #expect(throws: ShellXRoutineArgumentsError.usage) { try parse([]) }
    }

    @Test func bundleLayoutFromBundledCLI() throws {
        let layout = try #require(ShellXRoutineBundleLayout(cliPath: "/Applications/ShellX.app/Contents/Resources/bin/shellx"))
        #expect(layout.appPath == "/Applications/ShellX.app")
        #expect(layout.infoPlistPath == "/Applications/ShellX.app/Contents/Info.plist")
        #expect(layout.notifierAppPath == "/Applications/ShellX.app/Contents/Library/ShellX Notifier.app")
        #expect(layout.cliPath == "/Applications/ShellX.app/Contents/Resources/bin/shellx")
    }

    @Test func bundleLayoutRejectsLooseCLI() {
        #expect(ShellXRoutineBundleLayout(cliPath: "/usr/local/bin/shellx") == nil)
        #expect(ShellXRoutineBundleLayout(cliPath: "/tmp/Build/Products/Debug/shellx") == nil)
        #expect(ShellXRoutineBundleLayout(cliPath: "/x/Folder/Contents/Resources/bin/shellx") == nil)
    }
}

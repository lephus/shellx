import CmuxSidebar
import Foundation
import Testing

@Suite("Agent activity hook signals")
struct AgentActivityHookSignalTests {
    private func signal(_ subcommand: String, _ payload: String) -> AgentActivityHookSignal? {
        AgentActivityHookSignal(claudeSubcommand: subcommand, payload: payload)
    }

    /// Renders a payload the way Claude Code would, so scripts with quotes and
    /// newlines need no hand escaping.
    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func workflowPayload(script: String) throws -> String {
        try json(["tool_name": "Workflow", "tool_input": ["script": script]])
    }

    // MARK: prompt-submit

    @Test func promptSubmitPlainResets() {
        #expect(signal("prompt-submit", #"{"prompt":"fix the failing test"}"#) == .turnStarted(slashCommandName: nil))
        // A prompt-less payload still starts a turn.
        #expect(signal("prompt-submit", #"{"session_id":"s1"}"#) == .turnStarted(slashCommandName: nil))
        // A slash inside the text, a lone slash and a slash before a symbol are not commands.
        #expect(signal("prompt-submit", #"{"prompt":"open src/main.swift please"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"/"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"/ review"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"/-x"}"#) == .turnStarted(slashCommandName: nil))
        // A prompt that is not text carries no command.
        #expect(signal("prompt-submit", #"{"prompt":42}"#) == .turnStarted(slashCommandName: nil))
    }

    @Test func promptSubmitSlashCommandNamesSkill() {
        #expect(
            signal("prompt-submit", #"{"prompt":"/brainstorming add a login page"}"#)
                == .turnStarted(slashCommandName: "brainstorming")
        )
        // The name is the command word only, with or without arguments.
        #expect(signal("prompt-submit", #"{"prompt":"/commit"}"#) == .turnStarted(slashCommandName: "commit"))
        #expect(signal("prompt-submit", #"{"prompt":"/commit -m fix"}"#) == .turnStarted(slashCommandName: "commit"))
        // Whitespace, including a newline, may precede the slash.
        #expect(signal("prompt-submit", #"{"prompt":"  \n/review-pr 12"}"#) == .turnStarted(slashCommandName: "review-pr"))
        // Plugin-qualified names keep their colon, dots, dashes and underscores.
        #expect(
            signal("prompt-submit", #"{"prompt":"/superpowers:writing_plans.v2-beta now"}"#)
                == .turnStarted(slashCommandName: "superpowers:writing_plans.v2-beta")
        )
        // A later slash in the text does not rename the command.
        #expect(
            signal("prompt-submit", #"{"prompt":"/first then /second"}"#)
                == .turnStarted(slashCommandName: "first")
        )
    }

    @Test func promptSubmitCommandNameTag() {
        let expanded = #"{"prompt":"<command-message>commit</command-message>\n<command-name>/commit</command-name>\n<command-args>-m fix</command-args>"}"#
        #expect(signal("prompt-submit", expanded) == .turnStarted(slashCommandName: "commit"))
        // The slash inside the tag is optional.
        #expect(
            signal("prompt-submit", #"{"prompt":"<command-name>review-pr</command-name>"}"#)
                == .turnStarted(slashCommandName: "review-pr")
        )
        // The tag may follow other text, and plugin-qualified names stay whole.
        #expect(
            signal("prompt-submit", #"{"prompt":"Caveat: expanded.\n<command-name>/superpowers:brainstorming</command-name>"}"#)
                == .turnStarted(slashCommandName: "superpowers:brainstorming")
        )
        // An empty tag or one with a space in the name is not a command name.
        #expect(
            signal("prompt-submit", #"{"prompt":"<command-name></command-name>"}"#)
                == .turnStarted(slashCommandName: nil)
        )
        #expect(
            signal("prompt-submit", #"{"prompt":"<command-name>/two words</command-name>"}"#)
                == .turnStarted(slashCommandName: nil)
        )
        // A leading slash command wins over a tag that comes later.
        #expect(
            signal("prompt-submit", #"{"prompt":"/typed then <command-name>/tagged</command-name>"}"#)
                == .turnStarted(slashCommandName: "typed")
        )
    }

    // MARK: pre-tool-use

    @Test func preToolUseSkillReadsSkillName() {
        #expect(
            signal(
                "pre-tool-use",
                #"{"tool_name":"Skill","tool_input":{"skill":"superpowers:brainstorming","args":"login"}}"#
            ) == .skillInvoked(name: "superpowers:brainstorming")
        )
        // Surrounding whitespace is not part of the name.
        #expect(
            signal("pre-tool-use", #"{"tool_name":"Skill","tool_input":{"skill":"  pdf \n"}}"#)
                == .skillInvoked(name: "pdf")
        )
        // A missing, blank or non-text skill leaves the invocation unnamed.
        #expect(signal("pre-tool-use", #"{"tool_name":"Skill","tool_input":{}}"#) == .skillInvoked(name: nil))
        #expect(signal("pre-tool-use", #"{"tool_name":"Skill"}"#) == .skillInvoked(name: nil))
        #expect(signal("pre-tool-use", #"{"tool_name":"Skill","tool_input":{"skill":"   "}}"#) == .skillInvoked(name: nil))
        #expect(signal("pre-tool-use", #"{"tool_name":"Skill","tool_input":{"skill":42}}"#) == .skillInvoked(name: nil))
        #expect(signal("pre-tool-use", #"{"tool_name":"Skill","tool_input":"pdf"}"#) == .skillInvoked(name: nil))
    }

    @Test func preToolUseWorkflowReadsNameParam() throws {
        #expect(
            signal(
                "pre-tool-use",
                #"{"tool_name":"Workflow","tool_input":{"name":"deep-review","args":{"target":"src"}}}"#
            ) == .workflowLaunched(name: "deep-review")
        )
        // An explicit name wins over the name inside the script's meta.
        let both = try json([
            "tool_name": "Workflow",
            "tool_input": [
                "name": "explicit",
                "script": "export const meta = { name: 'from-meta', description: 'd' }",
            ],
        ])
        #expect(signal("pre-tool-use", both) == .workflowLaunched(name: "explicit"))
        // A blank name falls through to the script.
        let blank = try json([
            "tool_name": "Workflow",
            "tool_input": [
                "name": "  ",
                "script": "export const meta = { name: 'from-meta', description: 'd' }",
            ],
        ])
        #expect(signal("pre-tool-use", blank) == .workflowLaunched(name: "from-meta"))
    }

    @Test func preToolUseWorkflowReadsMetaName() throws {
        let script = """
        export const meta = {
          name: 'review-and-fix',
          description: 'Review the diff, then fix what the reviewers found',
          phases: [{ title: 'Review', detail: 'one reviewer per file' }],
        }
        phase('Review')
        """
        let payload = try workflowPayload(script: script)
        #expect(signal("pre-tool-use", payload) == .workflowLaunched(name: "review-and-fix"))

        // Double quotes and a one-line literal read the same way.
        let doubleQuoted = try workflowPayload(script: #"export const meta = { name: "audit-all", description: "d" }"#)
        #expect(signal("pre-tool-use", doubleQuoted) == .workflowLaunched(name: "audit-all"))

        // The name need not be the first key, and braces, quotes and comments around it
        // do not end the literal early.
        let reordered = """
        export const meta = {
          // the reviewers' brief
          description: 'Handles {unbalanced braces and "quotes" in text',
          phases: [{ title: 'One', detail: 'x' }],
          name: 'late-name',
        }
        """
        let reorderedPayload = try workflowPayload(script: reordered)
        #expect(signal("pre-tool-use", reorderedPayload) == .workflowLaunched(name: "late-name"))

        // A block comment hides its quotes and braces, and `//` inside a string is no comment.
        let commented = """
        export const meta = {
          /* don't stop at } or ' here */
          description: 'docs at https://example.com/path, then an open {',
          name: 'comment-safe',
        }
        """
        let commentedPayload = try workflowPayload(script: commented)
        #expect(signal("pre-tool-use", commentedPayload) == .workflowLaunched(name: "comment-safe"))

        // Windows line endings end a line comment too.
        let crlf = try workflowPayload(
            script: "export const meta = {\r\n  // it's a Windows file\r\n  name: 'crlf-name',\r\n}\r\n"
        )
        #expect(signal("pre-tool-use", crlf) == .workflowLaunched(name: "crlf-name"))
    }

    @Test func preToolUseWorkflowWithoutNameIsUnnamed() throws {
        #expect(signal("pre-tool-use", #"{"tool_name":"Workflow"}"#) == .workflowLaunched(name: nil))
        #expect(
            signal(
                "pre-tool-use",
                #"{"tool_name":"Workflow","tool_input":{"scriptPath":"/tmp/flow.js","resumeFromRunId":"r1"}}"#
            ) == .workflowLaunched(name: nil)
        )
        // A script with no meta literal is unnamed.
        let noMeta = try workflowPayload(script: "phase('Scan')\nconst out = { name: 'not-a-workflow-name' }")
        #expect(signal("pre-tool-use", noMeta) == .workflowLaunched(name: nil))
        // Only the meta literal names the workflow, never a name used later in the script.
        let nameOutsideMeta = try workflowPayload(
            script: "export const meta = { description: 'no name here' }\nconst other = { name: 'beta' }"
        )
        #expect(signal("pre-tool-use", nameOutsideMeta) == .workflowLaunched(name: nil))
        // An unterminated literal is read to the end of the script: a name written
        // before the damage is found, and none is invented after it.
        let cutOffAfterName = try workflowPayload(script: "export const meta = { name: 'cut-off', description: 'cut off")
        #expect(signal("pre-tool-use", cutOffAfterName) == .workflowLaunched(name: "cut-off"))
        let cutOffBeforeName = try workflowPayload(script: "export const meta = { description: 'cut off'")
        #expect(signal("pre-tool-use", cutOffBeforeName) == .workflowLaunched(name: nil))
        // An empty name is no name.
        let emptyName = try workflowPayload(script: "export const meta = { name: '', description: 'd' }")
        #expect(signal("pre-tool-use", emptyName) == .workflowLaunched(name: nil))
    }

    @Test func otherToolsAreIgnored() {
        // The cheap pre-check passes on the word, but the tool is not a skill or workflow.
        #expect(signal("pre-tool-use", #"{"tool_name":"Bash","tool_input":{"command":"ls ~/.claude/skills # Skill"}}"#) == nil)
        #expect(signal("pre-tool-use", #"{"tool_name":"Edit","tool_input":{"new_string":"Workflow"}}"#) == nil)
        // Lookalike tool names are not the tool.
        #expect(signal("pre-tool-use", #"{"tool_name":"SkillSearch","tool_input":{}}"#) == nil)
        #expect(signal("pre-tool-use", #"{"tool_name":"mcp__x__Workflow","tool_input":{}}"#) == nil)
        #expect(signal("pre-tool-use", #"{"tool_name":"skill","tool_input":{}}"#) == nil)
        // Payloads without either word are not even parsed.
        #expect(signal("pre-tool-use", #"{"tool_name":"Read","tool_input":{"file_path":"/tmp/a"}}"#) == nil)
        // The word appears, but there is no tool name to read.
        #expect(signal("pre-tool-use", #"{"tool_input":{"skill":"pdf"}}"#) == nil)
        #expect(signal("pre-tool-use", #"{"tool_name":42,"tool_input":{"skill":"Skill"}}"#) == nil)
    }

    // MARK: stop

    @Test func stopWithRunningBackgroundTask() {
        #expect(
            signal("stop", #"{"background_tasks":[{"id":"a","status":"completed"},{"id":"b","status":"running"}]}"#)
                == .turnEnded(hasBackgroundWork: true)
        )
        #expect(
            signal("stop", #"{"background_tasks":[{"id":"a","status":"completed"},{"id":"b","status":"failed"}]}"#)
                == .turnEnded(hasBackgroundWork: false)
        )
        #expect(signal("stop", #"{"background_tasks":[]}"#) == .turnEnded(hasBackgroundWork: false))
        // Older Claude Code versions report neither field.
        #expect(signal("stop", "{}") == .turnEnded(hasBackgroundWork: false))
        #expect(signal("stop", #"{"background_tasks":"running"}"#) == .turnEnded(hasBackgroundWork: false))
        #expect(signal("stop", #"{"background_tasks":[{"status":"RUNNING"}]}"#) == .turnEnded(hasBackgroundWork: false))
    }

    @Test func stopWithOnlyCronsHasNoBackgroundWork() {
        // A cron would otherwise keep a workflow marker alive forever.
        #expect(
            signal("stop", #"{"session_crons":[{"id":"c1","cron":"*/5 * * * *"}]}"#)
                == .turnEnded(hasBackgroundWork: false)
        )
        #expect(
            signal(
                "stop",
                #"{"session_crons":[{"id":"c1"}],"background_tasks":[{"id":"a","status":"completed"}]}"#
            ) == .turnEnded(hasBackgroundWork: false)
        )
        // A running task still counts when crons are present.
        #expect(
            signal(
                "stop",
                #"{"session_crons":[{"id":"c1"}],"background_tasks":[{"id":"a","status":"running"}]}"#
            ) == .turnEnded(hasBackgroundWork: true)
        )
    }

    @Test func stopFailureEndsTheTurnLikeStop() {
        // Claude's StopFailure arrives under the `stop` subcommand and reads the same way.
        let failure = #"{"hook_event_name":"StopFailure","error":"rate_limit","background_tasks":[{"status":"running"}]}"#
        #expect(signal("stop", failure) == .turnEnded(hasBackgroundWork: true))
        // The `stop-failure` name is accepted as well.
        #expect(signal("stop-failure", failure) == .turnEnded(hasBackgroundWork: true))
        #expect(signal("stop-failure", "{}") == .turnEnded(hasBackgroundWork: false))
    }

    // MARK: session-end and everything else

    @Test func sessionEndEndsTheSession() {
        #expect(signal("session-end", #"{"reason":"clear"}"#) == .sessionEnded)
        #expect(signal("session-end", "{}") == .sessionEnded)
        // Nothing in the payload matters to ending a session.
        #expect(signal("session-end", "") == .sessionEnded)
    }

    @Test func unknownSubcommandsAreIgnored() {
        let payload = #"{"prompt":"/commit","tool_name":"Skill","background_tasks":[{"status":"running"}]}"#
        for subcommand in [
            "session-start", "notification", "post-tool-use", "subagent-stop", "agent-response",
            "approval-response", "feed", "Stop", "PromptSubmit", "",
        ] {
            #expect(signal(subcommand, payload) == nil, "subcommand \(subcommand)")
        }
    }

    @Test func malformedPayloadIsIgnored() {
        let payloads = [
            "", "not json at all", "{", #"{"tool_name":"Skill""#, "[]", #""Skill""#, "null", "42", #"["Workflow"]"#,
        ]
        for subcommand in ["prompt-submit", "pre-tool-use", "stop", "stop-failure"] {
            for payload in payloads {
                #expect(signal(subcommand, payload) == nil, "\(subcommand) \(payload)")
            }
        }
    }
}

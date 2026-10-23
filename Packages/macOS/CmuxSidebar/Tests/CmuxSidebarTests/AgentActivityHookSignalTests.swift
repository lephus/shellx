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

    /// The text the way the app receives it: pulled back out of parsed JSON. With
    /// non-ASCII characters that is a string bridged from Foundation, which has no
    /// contiguous UTF-8 storage, rather than a native Swift string.
    private func asReceived(_ text: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["text": text])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object?["text"] as? String)
    }

    /// About 72 KiB of ASCII text that contains neither `Skill` nor `Workflow`.
    private static let asciiFiller = String(repeating: "abcdefghij ", count: 6_600)

    /// About 95 KiB of non-ASCII text that contains neither `Skill` nor `Workflow`.
    private static let vietnameseFiller = String(repeating: "Đã xong việc rồi nhé ", count: 3_400)

    private static let largePayloadSize = 64 * 1_024

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

    @Test func promptStartingWithPathIsNotASkill() {
        // A command name ends at whitespace or at the end of the prompt, so a path is no command.
        #expect(signal("prompt-submit", #"{"prompt":"/Users/me/notes.md please"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"/a/b"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"  \n/usr/local/bin/swift --version"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"/tmp/build.log"}"#) == .turnStarted(slashCommandName: nil))
        // A name cut short by punctuation that cannot be part of it is not a command either.
        #expect(signal("prompt-submit", #"{"prompt":"/commit,please"}"#) == .turnStarted(slashCommandName: nil))

        // Real commands still read, with arguments, with a newline after them, or alone.
        #expect(signal("prompt-submit", #"{"prompt":"/brainstorming"}"#) == .turnStarted(slashCommandName: "brainstorming"))
        #expect(
            signal("prompt-submit", #"{"prompt":"/brainstorming some args"}"#)
                == .turnStarted(slashCommandName: "brainstorming")
        )
        #expect(
            signal("prompt-submit", #"{"prompt":"/brainstorming\nsome args"}"#)
                == .turnStarted(slashCommandName: "brainstorming")
        )
        // Built-in commands parse like any other.
        #expect(signal("prompt-submit", #"{"prompt":"/clear"}"#) == .turnStarted(slashCommandName: "clear"))
    }

    @Test func promptCommandMustOpenThePrompt() throws {
        // The match is anchored to the start of the prompt, not to each of its lines.
        #expect(signal("prompt-submit", #"{"prompt":"hello\n/commit"}"#) == .turnStarted(slashCommandName: nil))
        #expect(signal("prompt-submit", #"{"prompt":"hello /commit"}"#) == .turnStarted(slashCommandName: nil))

        // Large prompts read the same way, with or without a command tag at the very end.
        let plain = try json(["prompt": Self.asciiFiller])
        #expect(plain.utf8.count >= Self.largePayloadSize)
        #expect(signal("prompt-submit", plain) == .turnStarted(slashCommandName: nil))
        let tagged = try json(["prompt": Self.asciiFiller + "<command-name>/deploy</command-name>"])
        #expect(signal("prompt-submit", tagged) == .turnStarted(slashCommandName: "deploy"))

        // The same when the text arrives bridged from Foundation.
        let receivedPlain = try asReceived(json(["prompt": Self.vietnameseFiller]))
        #expect(receivedPlain.utf8.count >= Self.largePayloadSize)
        #expect(signal("prompt-submit", receivedPlain) == .turnStarted(slashCommandName: nil))
        let receivedTagged = try asReceived(
            json(["prompt": Self.vietnameseFiller + "<command-name>/triển-khai</command-name>"])
        )
        #expect(signal("prompt-submit", receivedTagged) == .turnStarted(slashCommandName: "triển-khai"))
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

    @Test func preToolUseWorkflowReadsQuotedMetaName() throws {
        // JSON-style keys, double or single quoted, name the workflow like bare keys do.
        let doubleQuoted = try workflowPayload(
            script: #"export const meta = { "name": "quoted-flow", "description": "d" }"#
        )
        #expect(signal("pre-tool-use", doubleQuoted) == .workflowLaunched(name: "quoted-flow"))

        let singleQuoted = try workflowPayload(
            script: "export const meta = { 'name': 'single-quoted', 'description': 'd' }"
        )
        #expect(signal("pre-tool-use", singleQuoted) == .workflowLaunched(name: "single-quoted"))

        // The quoted key need not be first, may have space before its colon, and its value
        // may use the other kind of quote.
        let later = """
        export const meta = {
          "description": "Review the diff",
          "phases": [{ "title": "Review", "detail": "x" }],
          "name" : 'late-quoted',
        }
        """
        let laterPayload = try workflowPayload(script: later)
        #expect(signal("pre-tool-use", laterPayload) == .workflowLaunched(name: "late-quoted"))

        // A quoted key outside the meta literal still names nothing.
        let outside = try workflowPayload(
            script: #"export const meta = { "description": "no name" }"# + "\n" + #"const other = { "name": "beta" }"#
        )
        #expect(signal("pre-tool-use", outside) == .workflowLaunched(name: nil))

        // A key that merely ends in `name` is not the name, quoted or not.
        let lookalike = try workflowPayload(
            script: #"export const meta = { username: 'someone', "filename": "f.js", description: 'd' }"#
        )
        #expect(signal("pre-tool-use", lookalike) == .workflowLaunched(name: nil))
    }

    @Test func preToolUseWorkflowReadsNameAfterManyBlockComments() throws {
        // Thousands of comments inside the literal are skipped in one pass, and the name after them is found.
        let comments = String(repeating: "/* a */", count: 8_000)
        let ascii = try workflowPayload(script: "export const meta = {\n\(comments)\n  name: 'after-comments',\n}")
        #expect(signal("pre-tool-use", ascii) == .workflowLaunched(name: "after-comments"))

        // Empty comments are comments too.
        let empty = String(repeating: "/**/", count: 16_000)
        let emptyPayload = try workflowPayload(script: "export const meta = {\n\(empty)\n  name: 'after-empty',\n}")
        #expect(signal("pre-tool-use", emptyPayload) == .workflowLaunched(name: "after-empty"))

        // With a non-ASCII character in the script, which reaches the scanner as a string
        // bridged from Foundation.
        let nonASCII = try workflowPayload(
            script: "export const meta = {\n  /* café */\n\(comments)\n  name: 'après-commentaires',\n}"
        )
        #expect(signal("pre-tool-use", nonASCII) == .workflowLaunched(name: "après-commentaires"))

        // The `*` that opens a comment cannot also close it: `/*/` is not a whole comment.
        let tricky = try workflowPayload(script: "export const meta = {\n  /*/ } */\n  name: 'tricky-comment',\n}")
        #expect(signal("pre-tool-use", tricky) == .workflowLaunched(name: "tricky-comment"))
    }

    @Test func preToolUseWorkflowWithUnterminatedBlockCommentReadsEarlierName() throws {
        // A comment that never closes swallows the rest of the script, however long it is,
        // and the name written before it still counts.
        let filler = String(repeating: "z", count: 60_000)
        let named = try workflowPayload(
            script: "export const meta = { name: 'before-comment', description: 'd' /* never closed " + filler
        )
        #expect(signal("pre-tool-use", named) == .workflowLaunched(name: "before-comment"))

        let namedNonASCII = try workflowPayload(
            script: "export const meta = { name: 'trước-bình-luận', description: 'café' /* never closed " + filler
        )
        #expect(signal("pre-tool-use", namedNonASCII) == .workflowLaunched(name: "trước-bình-luận"))

        // With no name before it, none is invented.
        let nameless = try workflowPayload(script: "export const meta = { description: 'd' /* never closed " + filler)
        #expect(signal("pre-tool-use", nameless) == .workflowLaunched(name: nil))
    }

    @Test func preToolUseWorkflowReadsNameAfterEscapedQuotesAndTemplateLiterals() throws {
        // An escaped quote, an escaped backslash before a closing quote, and a template literal
        // holding quotes, braces and an escaped backtick all sit in front of the name.
        let script = #"""
        export const meta = {
          description: 'it\'s a "quoted" } brace',
          whenToUse: `template with 'single' and "double" quotes, a { and an escaped \` backtick`,
          path: 'C:\\temp\\',
          name: 'after-escapes',
        }
        """#
        let payload = try workflowPayload(script: script)
        #expect(signal("pre-tool-use", payload) == .workflowLaunched(name: "after-escapes"))

        let double = #"""
        export const meta = {
          description: "she said \"hi\" and left {",
          name: "after-double-quotes",
        }
        """#
        let doublePayload = try workflowPayload(script: double)
        #expect(signal("pre-tool-use", doublePayload) == .workflowLaunched(name: "after-double-quotes"))
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

    @Test func preToolUseSkipsLargePayloadsWithoutToolWords() throws {
        // Neither word appears, so the payload is not even parsed; the answer is the one parsing would give.
        let bash = try json(["tool_name": "Bash", "tool_input": ["command": "echo " + Self.asciiFiller]])
        #expect(bash.utf8.count >= Self.largePayloadSize)
        #expect(signal("pre-tool-use", bash) == nil)

        let bashNonASCII = try asReceived(
            json(["tool_name": "Bash", "tool_input": ["command": "echo " + Self.vietnameseFiller]])
        )
        #expect(bashNonASCII.utf8.count >= Self.largePayloadSize)
        #expect(signal("pre-tool-use", bashNonASCII) == nil)

        // The check reads the payload text itself, so a tool name spelled only through a JSON
        // escape (a backslash and `u0053` for the `S`) never reaches the parser.
        let escapedS = "\\" + "u0053"
        let escaped = #"{"tool_name":"\#(escapedS)kill","tool_input":{"skill":"pdf"}}"#
        #expect(escaped.contains(escapedS) && !escaped.contains("Skill") && !escaped.contains("Workflow"))
        #expect(signal("pre-tool-use", escaped) == nil)
    }

    @Test func preToolUseFindsToolWordsAnywhereInLargePayloads() throws {
        let half = String(Self.asciiFiller.prefix(Self.asciiFiller.count / 2))
        let halfNonASCII = String(Self.vietnameseFiller.prefix(Self.vietnameseFiller.count / 2))
        let skills = [
            // The word at the start, in the middle and at the very end of the payload.
            #"{"tool_name":"Skill","tool_input":{"skill":"pdf"},"padding":"\#(Self.asciiFiller)"}"#,
            #"{"padding":"\#(half)","tool_name":"Skill","tool_input":{"skill":"pdf"},"more":"\#(half)"}"#,
            #"{"padding":"\#(Self.asciiFiller)","tool_input":{"skill":"pdf"},"tool_name":"Skill"}"#,
            #"{"tool_name":"Skill","tool_input":{"skill":"pdf"},"padding":"\#(Self.vietnameseFiller)"}"#,
            #"{"padding":"\#(halfNonASCII)","tool_name":"Skill","tool_input":{"skill":"pdf"},"more":"\#(halfNonASCII)"}"#,
            #"{"padding":"\#(Self.vietnameseFiller)","tool_input":{"skill":"pdf"},"tool_name":"Skill"}"#,
        ]
        for payload in skills {
            #expect(payload.utf8.count >= Self.largePayloadSize)
            #expect(signal("pre-tool-use", payload) == .skillInvoked(name: "pdf"))
            // And as the app receives it, bridged from Foundation when the text is not ASCII.
            #expect(signal("pre-tool-use", try asReceived(payload)) == .skillInvoked(name: "pdf"))
        }

        let workflows = [
            #"{"tool_name":"Workflow","tool_input":{"name":"deep-review"},"padding":"\#(Self.asciiFiller)"}"#,
            #"{"padding":"\#(Self.asciiFiller)","tool_input":{"name":"deep-review"},"tool_name":"Workflow"}"#,
            #"{"padding":"\#(Self.vietnameseFiller)","tool_input":{"name":"deep-review"},"tool_name":"Workflow"}"#,
        ]
        for payload in workflows {
            #expect(payload.utf8.count >= Self.largePayloadSize)
            #expect(signal("pre-tool-use", payload) == .workflowLaunched(name: "deep-review"))
            #expect(signal("pre-tool-use", try asReceived(payload)) == .workflowLaunched(name: "deep-review"))
        }

        // A word that only appears inside another tool's large input passes the check, and the tool decides.
        let bashMentioningSkill = try json([
            "tool_name": "Bash",
            "tool_input": ["command": Self.asciiFiller + "Skill"],
        ])
        #expect(signal("pre-tool-use", bashMentioningSkill) == nil)
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

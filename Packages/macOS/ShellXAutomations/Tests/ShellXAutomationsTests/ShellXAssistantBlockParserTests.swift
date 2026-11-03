import Testing
@testable import ShellXAutomations

struct ShellXAssistantBlockParserTests {
    private let draftJSON = #"{"kind":"skill","name":"pr-digest","description":"Digest PRs","skillMarkdown":"---\nname: pr-digest\n---"}"#

    @Test func hidesDraftBlockFromChat() {
        var parser = ShellXAssistantBlockParser()
        let text = "Here you go.\n```shellx-draft\n\(draftJSON)\n```\nAnything else?"
        let visible = parser.ingest(delta: text)
        #expect(!visible.contains("shellx-draft"))
        #expect(!visible.contains("pr-digest"))
        #expect(visible.contains("Here you go."))
        #expect(visible.contains("Anything else?"))
        let result = parser.finish(fullText: text)
        #expect(result.draft?.name == "pr-digest")
        #expect(result.draft?.notify == ShellXNotifySettings(on: [], targets: []))
        #expect(result.draft?.steps == [])
        #expect(!result.visible.contains("```"))
        #expect(result.visible.contains("Anything else?"))
    }

    @Test func lastValidDraftWins() {
        let parser = ShellXAssistantBlockParser()
        let text = "```shellx-draft\n\(draftJSON)\n```\nmore\n```shellx-draft\n{\"kind\": \"skill\", oops\n```"
        let result = parser.finish(fullText: text)
        #expect(result.draft?.name == "pr-digest")
        #expect(!result.visible.contains("oops"))
    }

    @Test func laterValidDraftReplacesEarlier() {
        let parser = ShellXAssistantBlockParser()
        let second = draftJSON.replacingOccurrences(of: "pr-digest", with: "other")
        let text = "```shellx-draft\n\(draftJSON)\n```\n```shellx-draft\n\(second)\n```"
        #expect(parser.finish(fullText: text).draft?.name == "other")
    }

    @Test func unclosedFenceStaysHiddenAcrossDeltas() {
        var parser = ShellXAssistantBlockParser()
        var visible = ""
        for delta in ["Sure.\n``", "`shellx-", "draft\n{\"kind\":\"sk", "ill\"", ", \"name\":\"x\""] {
            visible += parser.ingest(delta: delta)
        }
        #expect(visible == "Sure.\n")
        let closed = parser.ingest(delta: "}\n```\nDone")
        #expect(closed == "Done")
    }

    @Test func parsesChoices() {
        var parser = ShellXAssistantBlockParser()
        let text = "When?\n```shellx-choices\n{\"question\":\"When?\",\"multi\":true,\"options\":[\"Done\",\"Failed\"]}\n```"
        let visible = parser.ingest(delta: text)
        #expect(visible == "When?\n")
        let result = parser.finish(fullText: text)
        #expect(result.choices == ShellXCreatorChoices(question: "When?", multi: true, options: ["Done", "Failed"]))
        #expect(result.visible == "When?")
        #expect(result.draft == nil)
    }

    @Test func plainCodeFencesStayVisible() {
        var parser = ShellXAssistantBlockParser()
        let text = "Run:\n```bash\nls -la\n```\nok"
        var visible = ""
        for ch in text { visible += parser.ingest(delta: String(ch)) }
        #expect(visible == text)
        #expect(parser.finish(fullText: text).visible == text)
    }

    @Test func missingFieldsDefault() {
        let parser = ShellXAssistantBlockParser()
        let text = "```shellx-draft\n{\"kind\":\"cronjob\",\"name\":\"n\",\"notify\":{\"on\":[\"done\"]}}\n```"
        let draft = parser.finish(fullText: text).draft
        #expect(draft?.kind == .cronjob)
        #expect(draft?.description == "")
        #expect(draft?.skillMarkdown == "")
        #expect(draft?.notify == ShellXNotifySettings(on: [.done], targets: []))
    }
}

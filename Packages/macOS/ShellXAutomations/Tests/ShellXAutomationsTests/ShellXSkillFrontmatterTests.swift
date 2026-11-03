import Testing
@testable import ShellXAutomations

struct ShellXSkillFrontmatterTests {
    @Test func parsesPlainAndQuotedValues() throws {
        let f = try ShellXSkillFrontmatter(markdown: "---\nname: pr-digest\ndescription: \"Summarize: PRs\"\n---\nBody")
        #expect(f.name == "pr-digest")
        #expect(f.description == "Summarize: PRs")
        let g = try ShellXSkillFrontmatter(markdown: "---\r\nname: 'a'\r\ndescription: b\r\n---\r\n")
        #expect(g.name == "a")
        #expect(g.description == "b")
    }

    @Test func missingOpeningThrows() {
        #expect(throws: ShellXSkillFrontmatter.ParseError.missingOpening) {
            try ShellXSkillFrontmatter(markdown: "name: x\n---")
        }
    }

    @Test func missingClosingThrows() {
        #expect(throws: ShellXSkillFrontmatter.ParseError.missingClosing) {
            try ShellXSkillFrontmatter(markdown: "---\nname: x\n")
        }
    }

    @Test func missingNameThrows() {
        #expect(throws: ShellXSkillFrontmatter.ParseError.missingName) {
            try ShellXSkillFrontmatter(markdown: "---\ndescription: x\n---\n")
        }
    }
}

import XCTest

@testable import ShellXAppCore

final class AgentLabelTests: XCTestCase {
    func testKnownAgentsNamed() {
        XCTAssertEqual(AgentLabel(agent: "claude").text, "Claude Code")
        XCTAssertEqual(AgentLabel(agent: "codex").text, "Codex")
    }

    func testUnknownAgentKeptAsIs() {
        XCTAssertEqual(AgentLabel(agent: "gemini").text, "gemini")
        XCTAssertEqual(AgentLabel(agent: "Claude").text, "Claude", "wire names are exact")
        XCTAssertEqual(AgentLabel(agent: "").text, "")
    }
}

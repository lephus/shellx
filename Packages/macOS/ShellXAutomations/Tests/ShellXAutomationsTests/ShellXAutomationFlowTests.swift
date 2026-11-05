import Foundation
import Testing
@testable import ShellXAutomations

struct ShellXAutomationFlowTests {
    static let json = #"{"trigger":"When the disk is full","nodes":[{"id":"measure","type":"step","label":"Measure"},{"id":"ok","type":"askUser","label":"Approve?"},{"id":"stop","type":"end","label":"Stop"}],"edges":[{"from":"measure","to":"ok"},{"from":"ok","to":"stop","label":"No"}]}"#

    private func decode(_ text: String) throws -> ShellXAutomationFlow {
        try JSONDecoder().decode(ShellXAutomationFlow.self, from: Data(text.utf8))
    }

    @Test func decodesClaudeJSON() throws {
        let flow = try decode(Self.json)
        #expect(flow.nodes.count == 3)
        #expect(flow.nodes[1].type == .askUser)
        #expect(flow.edges[1].label == "No")
    }

    @Test func isUsableRejects() throws {
        let good = try decode(Self.json)
        #expect(good.isUsable)

        var empty = good
        empty.nodes = []
        empty.edges = []
        #expect(!empty.isUsable)

        var duplicate = good
        duplicate.nodes[1].id = "measure"
        #expect(!duplicate.isUsable)

        var dangling = good
        dangling.edges[0].to = "missing"
        #expect(!dangling.isUsable)
    }

    @Test func fingerprintIsSHA256() {
        #expect(ShellXFlowFingerprint.of("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

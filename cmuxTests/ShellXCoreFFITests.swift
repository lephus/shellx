import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// ShellX: shellx-core is linked statically; the app reaches it through the C ABI.
@Suite struct ShellXCoreFFITests {
    @Test func coreAnswersThroughFFI() async throws {
        let out = try await Task.detached { try ShellXCoreFFI.shared.call(method: "nope", json: Data("{}".utf8)) }.value
        #expect(String(decoding: out, as: UTF8.self).contains("\"unknown_method\""))
    }
}

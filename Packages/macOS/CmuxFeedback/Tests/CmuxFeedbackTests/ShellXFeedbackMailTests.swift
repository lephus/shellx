import Foundation
import Testing

@testable import CmuxFeedback

/// ShellX takes feedback by mail: no HTTP endpoint, a mailto draft to ShellX.
@Suite struct ShellXFeedbackMailTests {
    @Test func feedbackUsesMail() {
        #expect(FeedbackComposerSettings.submissionURL.absoluteString == "mailto:phule9225@gmail.com")
        #expect(FeedbackComposerSettings.submissionURL.scheme == "mailto")
    }

    @Test func noDefaultUploadEndpoint() {
        let settings = FeedbackComposerSettings()
        #expect(settings.defaultEndpoint.isEmpty)
        #expect(settings.endpointURL(environment: [:]) == nil)
        #expect(settings.foundersEmail == "phule9225@gmail.com")
    }

    @Test func submitFailsClosedWithoutNetworkAndPointsAtShellXMail() async {
        do {
            _ = try await FeedbackComposerBridge().submit(
                email: "valid@example.com",
                message: "Real message",
                imagePaths: []
            )
            Issue.record("submit must not succeed without an endpoint")
        } catch let FeedbackComposerBridgeError.submissionFailed(message) {
            #expect(message.contains("phule9225@gmail.com"))
            #expect(!message.contains("cmux.com"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

import Foundation
import XCTest

@testable import ShellXAppCore

/// What the composer keeps once a message with attachments is answered: what went is cleared, what
/// was added meanwhile (a photo still loading when Send was tapped) stays, and nothing is cleared
/// when the message is to be sent again.
final class ComposerDraftTests: XCTestCase {
    private func attachment(_ name: String) -> OutgoingAttachment {
        OutgoingAttachment(kind: .image, name: name, data: Data(name.utf8))
    }

    func testLateAttachmentSurvivesASuccessfulSend() {
        let first = attachment("photo-1.jpg")
        let second = attachment("photo-2.jpg")
        let late = attachment("photo-3.jpg")
        var draft = ComposerDraft(text: "sửa lỗi này", attachments: [first, second])

        draft.sendStarted()
        XCTAssertTrue(draft.isSending)
        // The third photo finishes loading while the first two go up.
        draft.attachments.append(late)
        draft.sendEnded(keepsDraft: false)

        XCTAssertFalse(draft.isSending)
        XCTAssertEqual(draft.text, "")
        XCTAssertEqual(draft.attachments, [late], "only what went is cleared")
    }

    func testMessageToSendAgainKeepsEverything() {
        let first = attachment("photo-1.jpg")
        let late = attachment("photo-2.jpg")
        var draft = ComposerDraft(text: "sửa lỗi này", attachments: [first])

        draft.sendStarted()
        draft.attachments.append(late)
        draft.sendEnded(keepsDraft: true)

        XCTAssertFalse(draft.isSending)
        XCTAssertEqual(draft.text, "sửa lỗi này")
        XCTAssertEqual(draft.attachments, [first, late])
    }

    func testAnswerWithoutASendChangesNothing() {
        let first = attachment("photo-1.jpg")
        var draft = ComposerDraft(text: "chưa gửi", attachments: [first])

        draft.sendEnded(keepsDraft: false)

        XCTAssertEqual(draft, ComposerDraft(text: "chưa gửi", attachments: [first]))
    }
}

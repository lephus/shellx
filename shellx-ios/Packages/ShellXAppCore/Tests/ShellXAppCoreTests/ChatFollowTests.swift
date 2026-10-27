import XCTest

@testable import ShellXAppCore

/// Whether a new entry scrolls the chat down: only while its bottom shows. Otherwise the user is
/// reading older entries, and a "New messages" notice says that more came below.
final class ChatFollowTests: XCTestCase {
    func testFollowsOnlyWhileTheBottomShows() {
        var follow = ChatFollow()
        XCTAssertTrue(follow.newest("e1"), "the first entries come into view")
        XCTAssertTrue(follow.newest("e2"), "at the bottom: follow")
        XCTAssertFalse(follow.newest("e2"), "the same newest entry (an older page came in above): nothing")
        XCTAssertFalse(follow.hasUnseen)

        // The user scrolls up to read.
        follow.bottomVisible(false)
        XCTAssertFalse(follow.newest("e3"), "never pulled down while reading")
        XCTAssertTrue(follow.hasUnseen)
        XCTAssertFalse(follow.newest("e4"))
        XCTAssertTrue(follow.hasUnseen)

        // Scrolling back down by hand clears the notice, and new entries are followed again.
        follow.bottomVisible(true)
        XCTAssertFalse(follow.hasUnseen)
        XCTAssertTrue(follow.newest("e5"))

        // Tapping "New messages" jumps down and clears it.
        follow.bottomVisible(false)
        _ = follow.newest("e6")
        XCTAssertTrue(follow.hasUnseen)
        follow.jumpedToBottom()
        XCTAssertFalse(follow.hasUnseen)
        XCTAssertTrue(follow.newest("e7"))

        // A chat that empties has nothing to follow.
        XCTAssertFalse(follow.newest(nil))
        XCTAssertFalse(follow.hasUnseen)
    }
}

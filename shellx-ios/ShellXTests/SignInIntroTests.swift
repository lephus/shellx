import XCTest
@testable import ShellX

/// The sign-in intro's decisions that need no screen: when it moves at all, how the chevrons slide, when the
/// underscore blinks, what the typed tagline shows at a given moment, when the guide rows appear, and how the
/// screen lays itself out by its size.
final class SignInIntroTests: XCTestCase {
    // MARK: - Whether it moves

    func testReduceMotionAndTestsKeepTheIntroStill() {
        XCTAssertEqual(SignInIntroMotion.decide(reduceMotion: false, underTest: false), .animated)
        XCTAssertEqual(SignInIntroMotion.decide(reduceMotion: true, underTest: false), .still)
        XCTAssertEqual(SignInIntroMotion.decide(reduceMotion: false, underTest: true), .still)
        XCTAssertEqual(SignInIntroMotion.decide(reduceMotion: true, underTest: true), .still)
    }

    func testATestRunOrAScreenshotRunIsRecognisedFromTheEnvironment() {
        XCTAssertFalse(SignInIntroMotion.isUnderTest(environment: [:]))
        XCTAssertFalse(SignInIntroMotion.isUnderTest(environment: ["PATH": "/usr/bin", "SHELLX_DEMO": "1"]))
        XCTAssertTrue(SignInIntroMotion.isUnderTest(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        XCTAssertTrue(SignInIntroMotion.isUnderTest(environment: ["XCTestSessionIdentifier": "ABC"]))
        XCTAssertTrue(SignInIntroMotion.isUnderTest(environment: ["SHELLX_SNAPSHOT_DIR": "/tmp/shots"]))
        XCTAssertFalse(SignInIntroMotion.isUnderTest(environment: ["SHELLX_SNAPSHOT_DIR": ""]), "an empty directory is no screenshot run")
        XCTAssertTrue(SignInIntroMotion.underTest, "this very run is a test run, so every render in it is still")
    }

    // MARK: - The chevrons' slide

    func testTheChevronsStartOutsideAndSettleWithinSixHundredMilliseconds() {
        XCTAssertEqual(SignInIntro.slideProgress(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.slideProgress(at: -1), 0, accuracy: 1e-9, "before the start nothing has moved")
        XCTAssertEqual(SignInIntro.slideProgress(at: SignInIntro.chevronSettle), 1, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.slideProgress(at: 5), 1, accuracy: 1e-9, "and it stays put")
        XCTAssertEqual(SignInIntro.chevronSettle, 0.6, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(SignInIntro.end, 0.9, "the whole intro takes about 900 ms")
        XCTAssertGreaterThan(SignInIntro.chevronStart, 0.49, "the chevrons begin fully outside the square (they reach 249/512 of its side)")
    }

    func testTheSlideEasesOutAndOvershootsByAtMostFourPercent() {
        var previous = 0.0
        var peak = 0.0
        for step in 0...600 {
            let t = Double(step) / 1000
            let progress = SignInIntro.slideProgress(at: t)
            XCTAssertLessThanOrEqual(progress, 1 + 0.04 + 1e-9, "at \(t) s")
            if t <= 0.45 {
                XCTAssertGreaterThanOrEqual(progress, previous - 1e-9, "the slide in never goes backwards (\(t) s)")
            } else {
                XCTAssertLessThanOrEqual(progress, previous + 1e-9, "after the peak it only settles back (\(t) s)")
                XCTAssertGreaterThanOrEqual(progress, 1 - 1e-9, "and never falls short of the rest position (\(t) s)")
            }
            peak = max(peak, progress)
            previous = progress
        }
        XCTAssertGreaterThan(peak, 1.03, "there is a visible overshoot")
        XCTAssertLessThanOrEqual(peak, 1.04 + 1e-9)
        // Ease-out: the first half of the rise covers most of the way.
        XCTAssertGreaterThan(SignInIntro.slideProgress(at: 0.225), 0.8)
    }

    func testTheLeftChevronComesFromTheLeftAndTheRightOneFromTheRight() {
        XCTAssertEqual(SignInIntro.chevronOffset(at: 0), -SignInIntro.chevronStart, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.chevronOffset(at: 1), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(SignInIntro.chevronOffset(at: 0.45), 0, "at the peak it is a little past its place")
        XCTAssertLessThanOrEqual(SignInIntro.chevronOffset(at: 0.45), 0.04 * SignInIntro.chevronStart + 1e-9)
        XCTAssertEqual(SignInIntro.rightChevronOffset(at: 0), SignInIntro.chevronStart, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.rightChevronOffset(at: 0.3), -SignInIntro.chevronOffset(at: 0.3), accuracy: 1e-9)
    }

    // MARK: - The underscore and the cursors

    func testTheUnderscoreAppearsAfterTheChevronsThenBlinks() {
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: 0), 0)
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: 0.59), 0)
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: 0.675), 0.5, accuracy: 0.01, "half way through its fade")
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: 0.75), 1)
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: SignInIntro.end), 1, "the blink starts with the cursor on")
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: SignInIntro.end + 0.53), 0, "off after 530 ms")
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: SignInIntro.end + 1.06), 1, "on again after 1060 ms")
        XCTAssertEqual(SignInIntro.underscoreOpacity(at: SignInIntro.end + 60 * 1.06 + 0.6), 0, "still blinking a minute later")
    }

    func testACursorBlinksOnAndOffEvery530Milliseconds() {
        XCTAssertEqual(CursorBlink.half, 0.53, accuracy: 1e-9)
        XCTAssertTrue(CursorBlink.isOn(elapsed: 0))
        XCTAssertTrue(CursorBlink.isOn(elapsed: 0.52))
        XCTAssertFalse(CursorBlink.isOn(elapsed: 0.53))
        XCTAssertFalse(CursorBlink.isOn(elapsed: 1.05))
        XCTAssertTrue(CursorBlink.isOn(elapsed: 1.06))
        XCTAssertTrue(CursorBlink.isOn(elapsed: -2), "before its start a cursor is simply on")
        XCTAssertTrue(CursorBlink.isOn(elapsed: 1_000_000 * 1.06 + 0.1), "no overflow, however long the screen stays")
    }

    // MARK: - The typed tagline

    private let schedule = TypewriterSchedule(lines: ["Hello", "Bye"])

    func testTheDefaultSpeedsAreTheAgreedOnes() {
        XCTAssertEqual(schedule.typeInterval, 0.028, accuracy: 1e-9)
        XCTAssertEqual(schedule.hold, 2.4, accuracy: 1e-9)
        XCTAssertEqual(schedule.eraseInterval, 0.012, accuracy: 1e-9)
        XCTAssertEqual(schedule.pause, 0.3, accuracy: 1e-9)
        XCTAssertEqual(TypedTaglineView.startDelay, SignInIntro.chevronSettle, accuracy: 1e-9, "typing starts once the logo has settled")
    }

    func testEachLineIsTypedHeldErasedThenPaused() {
        let n = 5.0
        XCTAssertEqual(schedule.lineDuration(0), n * 0.028 + 2.4 + n * 0.012 + 0.3, accuracy: 1e-9)
        XCTAssertEqual(schedule.cycle, schedule.lineDuration(0) + schedule.lineDuration(1), accuracy: 1e-9)

        let typing = schedule.frame(at: 0)
        XCTAssertEqual(typing.line, 0)
        XCTAssertEqual(typing.text, "H", "the first letter shows the moment typing starts")
        XCTAssertEqual(typing.phase, .typing)
        XCTAssertEqual(typing.nextChange, 0.028, accuracy: 1e-9)

        XCTAssertEqual(schedule.frame(at: 0.028 * 3).text, "Hell")
        XCTAssertEqual(schedule.frame(at: 0.028 * 3 + 0.01).text, "Hell")
        XCTAssertEqual(schedule.frame(at: 0.028 * 4).text, "Hello")
        XCTAssertEqual(schedule.frame(at: 0.028 * 4).phase, .typing, "the last letter is held one beat before the hold")
        XCTAssertEqual(schedule.frame(at: 0.028 * 4).nextChange, 0.028 * 5, accuracy: 1e-9)

        let holding = schedule.frame(at: 0.028 * 5 + 1)
        XCTAssertEqual(holding.text, "Hello")
        XCTAssertEqual(holding.phase, .holding)
        XCTAssertEqual(holding.nextChange, 0.028 * 5 + 2.4, accuracy: 1e-9)

        let erasing = schedule.frame(at: 0.028 * 5 + 2.4)
        XCTAssertEqual(erasing.phase, .erasing)
        XCTAssertEqual(erasing.text, "Hell", "the first letter goes the moment erasing starts")
        XCTAssertEqual(erasing.nextChange, 0.028 * 5 + 2.4 + 0.012, accuracy: 1e-9)
        XCTAssertEqual(schedule.frame(at: 0.028 * 5 + 2.4 + 0.012 * 4).text, "")
        XCTAssertEqual(schedule.frame(at: 0.028 * 5 + 2.4 + 0.012 * 4).phase, .erasing)

        let pausing = schedule.frame(at: 0.028 * 5 + 2.4 + 0.012 * 5 + 0.1)
        XCTAssertEqual(pausing.phase, .pausing)
        XCTAssertEqual(pausing.text, "")
        XCTAssertEqual(pausing.line, 0)
        XCTAssertEqual(pausing.nextChange, schedule.lineDuration(0), accuracy: 1e-9)

        let second = schedule.frame(at: schedule.lineDuration(0))
        XCTAssertEqual(second.line, 1)
        XCTAssertEqual(second.text, "B")
        XCTAssertEqual(second.phase, .typing)
    }

    func testTheLinesCycleForever() {
        let later = schedule.frame(at: schedule.cycle * 3 + 0.05)
        let early = schedule.frame(at: 0.05)
        XCTAssertEqual(later.line, early.line)
        XCTAssertEqual(later.text, early.text)
        XCTAssertEqual(later.phase, early.phase)
        XCTAssertEqual(later.nextChange, early.nextChange + schedule.cycle * 3, accuracy: 1e-6)
        XCTAssertEqual(schedule.frame(at: 1_000_000).line, schedule.frame(at: 1_000_000 - schedule.cycle).line, "no overflow for a long stay")
    }

    func testBeforeTheStartTheLineIsEmptyAndTheNextChangeIsTheStart() {
        let before = schedule.frame(at: -0.4)
        XCTAssertEqual(before.text, "")
        XCTAssertEqual(before.line, 0)
        XCTAssertEqual(before.phase, .pausing)
        XCTAssertEqual(before.nextChange, 0, accuracy: 1e-9)
    }

    func testTheNextChangeIsAlwaysLaterAndReallyChangesTheFrame() {
        var t = -0.1
        var frames = 0
        while t < schedule.cycle * 2 {
            let frame = schedule.frame(at: t)
            XCTAssertGreaterThan(frame.nextChange, t, "at \(t)")
            let next = schedule.frame(at: frame.nextChange)
            XCTAssertTrue(
                next.text != frame.text || next.phase != frame.phase || next.line != frame.line,
                "the frame at \(frame.nextChange) (after \(t)) should differ: \(frame) -> \(next)")
            t = frame.nextChange
            frames += 1
        }
        // 2 cycles x (5 + 5 + 3 + 3 letters typed and erased + 2 holds + 2 pauses) changes, plus the start.
        XCTAssertEqual(frames, 2 * (5 + 5 + 3 + 3 + 2 + 2) + 1)
    }

    func testLettersAreCountedAsTheUserSeesThem() {
        // "e" + combining acute is one letter on screen; Vietnamese from the catalog is precomposed but may not stay so.
        let accents = TypewriterSchedule(lines: ["Đe\u{301}n"])
        XCTAssertEqual(accents.lineDuration(0), 3 * 0.028 + 2.4 + 3 * 0.012 + 0.3, accuracy: 1e-9)
        XCTAssertEqual(accents.frame(at: 0.028).text, "Đe\u{301}", "a combining mark never shows on its own")
    }

    func testWithoutLinesNothingIsTypedAndNothingIsScheduled() {
        let empty = TypewriterSchedule(lines: [])
        let frame = empty.frame(at: 3)
        XCTAssertEqual(frame.text, "")
        XCTAssertEqual(frame.nextChange, .infinity)
        XCTAssertEqual(empty.cycle, 0)
    }

    func testTheTaglinesAreTheThreeFromTheCatalogInOrder() {
        let lines = TypedTaglineView.lines()
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines, [
            String(localized: "signin.tagline.1"), String(localized: "signin.tagline.2"), String(localized: "signin.tagline.3"),
        ])
        XCTAssertEqual(Set(lines).count, 3, "three different lines")
    }

    // MARK: - The guide

    func testTheGuideRowsFollowTheLogoEightyMillisecondsApart() {
        XCTAssertEqual(SignInGuideView.rows, 3)
        XCTAssertEqual(SignInGuideView.revealTime(row: 0), SignInIntro.chevronSettle, accuracy: 1e-9)
        XCTAssertEqual(SignInGuideView.revealTime(row: 1), SignInIntro.chevronSettle + 0.08, accuracy: 1e-9)
        XCTAssertEqual(SignInGuideView.revealTime(row: 2), SignInIntro.chevronSettle + 0.16, accuracy: 1e-9)
        XCTAssertEqual(SignInGuideView.fade, 0.25, accuracy: 1e-9)
        XCTAssertEqual(SignInGuideView.slide, 8)
    }

    // MARK: - Layout

    func testAPhoneInPortraitGetsTheFullLogoAndTheGuide() {
        let iphone16 = SignInLayout(size: CGSize(width: 393, height: 759))
        XCTAssertEqual(iphone16.logoSize, 96)
        XCTAssertTrue(iphone16.showsSubtitle, "tall enough for the subtitle under the taglines")
        XCTAssertTrue(iphone16.showsGuide)
        XCTAssertFalse(iphone16.sideBySide)

        let se = SignInLayout(size: CGSize(width: 375, height: 647))
        XCTAssertEqual(se.logoSize, 96)
        XCTAssertFalse(se.showsSubtitle, "under 700 points the taglines replace the subtitle")
        XCTAssertTrue(se.showsGuide)
        XCTAssertFalse(se.sideBySide)
    }

    func testAShortOrSidewaysWindowShrinksTheLogo() {
        XCTAssertEqual(SignInLayout(size: CGSize(width: 360, height: 599)).logoSize, 72)
        XCTAssertEqual(SignInLayout(size: CGSize(width: 360, height: 600)).logoSize, 96)
        XCTAssertEqual(SignInLayout(size: CGSize(width: 1000, height: 800)).logoSize, 72, "landscape, however tall")
    }

    func testLandscapePutsTheLogoBesideTheButtonsAndHidesTheGuideUnder400Points() {
        let iphone16 = SignInLayout(size: CGSize(width: 734, height: 372))
        XCTAssertTrue(iphone16.sideBySide)
        XCTAssertEqual(iphone16.logoSize, 72)
        XCTAssertFalse(iphone16.showsGuide)
        XCTAssertFalse(iphone16.showsSubtitle)

        let proMax = SignInLayout(size: CGSize(width: 838, height: 419))
        XCTAssertTrue(proMax.sideBySide)
        XCTAssertTrue(proMax.showsGuide, "400 points or more fit the three rows beside the buttons")
    }

    func testNothingShowsForAnEmptySizeExceptWhatAlwaysShows() {
        let zero = SignInLayout(size: .zero)
        XCTAssertEqual(zero.logoSize, 72)
        XCTAssertFalse(zero.showsGuide)
        XCTAssertFalse(zero.showsSubtitle)
        XCTAssertFalse(zero.sideBySide)
    }
}

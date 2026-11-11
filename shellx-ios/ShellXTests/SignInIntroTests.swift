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

    func testAPhoneInPortraitGetsTheLogoTheStepsAndTheSubtitleItHasRoomFor() {
        // iPhone 16 Pro Max upright: 440 x 860 points inside the safe area.
        let proMax = SignInLayout(size: CGSize(width: 440, height: 860))
        XCTAssertEqual(proMax.logoSize, 96)
        XCTAssertTrue(proMax.showsSubtitle, "tall enough for the subtitle under the taglines")
        XCTAssertTrue(proMax.showsGuide)
        XCTAssertTrue(proMax.showsTaglines)

        // iPhone 16 Plus: 430 x 839.
        let plus = SignInLayout(size: CGSize(width: 430, height: 839))
        XCTAssertFalse(plus.showsSubtitle, "the email field and Send code take the subtitle's room")
        XCTAssertTrue(plus.showsGuide)

        // iPhone 16: 393 x 759.
        let iphone16 = SignInLayout(size: CGSize(width: 393, height: 759))
        XCTAssertEqual(iphone16.logoSize, 96)
        XCTAssertFalse(iphone16.showsSubtitle)
        XCTAssertTrue(iphone16.showsGuide)
        XCTAssertTrue(iphone16.showsTaglines)
        XCTAssertFalse(iphone16.sideBySide)

        // iPhone SE: 375 x 647.
        let se = SignInLayout(size: CGSize(width: 375, height: 647))
        XCTAssertEqual(se.logoSize, 96, "the steps give way before the large logo")
        XCTAssertFalse(se.showsSubtitle)
        XCTAssertFalse(se.showsGuide)
        XCTAssertTrue(se.showsTaglines)
        XCTAssertFalse(se.sideBySide)
    }

    func testTheIntroGivesWayToTheFieldSubtitleFirstThenTheStepsThenTheLargeLogo() {
        XCTAssertGreaterThan(SignInLayout.subtitleHeight, SignInLayout.guideHeight)
        XCTAssertGreaterThan(SignInLayout.guideHeight, SignInLayout.largeLogoHeight)
        func layout(_ height: CGFloat) -> SignInLayout { SignInLayout(size: CGSize(width: 375, height: height)) }
        XCTAssertEqual(SignInLayout.subtitleHeight, 845)
        XCTAssertTrue(layout(845).showsSubtitle)
        XCTAssertFalse(layout(844).showsSubtitle)
        XCTAssertEqual(SignInLayout.guideHeight, 756)
        XCTAssertTrue(layout(756).showsGuide)
        XCTAssertFalse(layout(755).showsGuide)
        XCTAssertEqual(layout(755).logoSize, 96)
        XCTAssertEqual(SignInLayout.largeLogoHeight, 595)
        XCTAssertEqual(layout(595).logoSize, 96)
        XCTAssertEqual(layout(594).logoSize, 72)
    }

    func testAShortOrSidewaysWindowShrinksTheLogo() {
        XCTAssertEqual(SignInLayout(size: CGSize(width: 375, height: 594)).logoSize, 72)
        XCTAssertEqual(SignInLayout(size: CGSize(width: 375, height: 595)).logoSize, 96)
        XCTAssertEqual(SignInLayout(size: CGSize(width: 1000, height: 800)).logoSize, 72, "on its side, however tall")
    }

    func testLandscapePutsTheLogoBesideTheFieldAndShowsTheStepsOnlyWhereTheyFit() {
        let iphone16 = SignInLayout(size: CGSize(width: 734, height: 372))
        XCTAssertTrue(iphone16.sideBySide)
        XCTAssertEqual(iphone16.logoSize, 72)
        XCTAssertFalse(iphone16.showsGuide)
        XCTAssertFalse(iphone16.showsSubtitle)
        XCTAssertTrue(iphone16.showsTaglines)

        let proMax = SignInLayout(size: CGSize(width: 832, height: 419))
        XCTAssertTrue(proMax.sideBySide)
        XCTAssertFalse(proMax.showsGuide, "the field and Send code take the steps' room beside the intro")

        XCTAssertEqual(SignInLayout.sidewaysGuideHeight, 525)
        XCTAssertTrue(SignInLayout(size: CGSize(width: 832, height: 525)).showsGuide)
        XCTAssertFalse(SignInLayout(size: CGSize(width: 832, height: 524)).showsGuide)
        XCTAssertFalse(SignInLayout(size: CGSize(width: 832, height: 900)).showsSubtitle, "never on its side")
    }

    func testTheKeyboardNeverTurnsTheScreenOnItsSide() {
        // An iPhone SE upright under a tall keyboard, a Pro Max upright under one, then two phones on their side.
        let sizes = [CGSize(width: 375, height: 300), CGSize(width: 440, height: 250), CGSize(width: 667, height: 375), CGSize(width: 734, height: 160)]
        XCTAssertEqual(sizes.map { SignInLayout(size: $0).sideBySide }, [false, false, true, true])
        XCTAssertEqual(SignInLayout.sidewaysWidth, 500)
    }

    func testFoldedTheIntroKeepsASmallLogoAndTheTitleWhateverTheRoom() {
        for size in [CGSize(width: 393, height: 759), CGSize(width: 375, height: 387), CGSize(width: 430, height: 839), CGSize(width: 734, height: 160)] {
            let folded = SignInLayout(size: size, folded: true)
            XCTAssertEqual(folded.logoSize, 48, "\(size)")
            XCTAssertFalse(folded.showsTaglines, "\(size)")
            XCTAssertFalse(folded.showsSubtitle, "\(size)")
            XCTAssertFalse(folded.showsGuide, "\(size)")
            XCTAssertEqual(folded.sideBySide, SignInLayout(size: size).sideBySide, "folding never changes the columns (\(size))")
        }
    }

    func testNothingShowsForAnEmptySizeExceptWhatAlwaysShows() {
        let zero = SignInLayout(size: .zero)
        XCTAssertEqual(zero.logoSize, 72)
        XCTAssertFalse(zero.showsGuide)
        XCTAssertFalse(zero.showsSubtitle)
        XCTAssertFalse(zero.sideBySide)
        XCTAssertTrue(zero.showsTaglines)
    }

    func testTheEmailFieldAsksForAnEnglishKeyboardWhenTheUserHasOne() {
        XCTAssertEqual(EmailKeyboard.preferred(among: ["vi-VN", "emoji", "en-US"]), 2)
        XCTAssertEqual(EmailKeyboard.preferred(among: [nil, "EN-GB", "en-US"]), 1)
        XCTAssertEqual(EmailKeyboard.preferred(among: ["en"]), 0)
        XCTAssertNil(EmailKeyboard.preferred(among: ["vi-VN", "emoji", "dictation"]), "no English keyboard: the system chooses")
        XCTAssertNil(EmailKeyboard.preferred(among: []))
    }

    // MARK: - The halo

    /// How far two angles are apart, in degrees, the short way round.
    private func apart(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    func testTheHaloTurnsClockwiseOnceEverySixSecondsFromItsStart() {
        let start = SignInIntro.chevronSettle
        XCTAssertEqual(SignInIntro.haloTurn, 6)
        XCTAssertEqual(SignInIntro.haloAngle(at: 0), 0, "before the halo is there, nothing has turned")
        XCTAssertEqual(SignInIntro.haloAngle(at: start), 0, "it starts when the chevrons have settled")
        XCTAssertEqual(SignInIntro.haloAngle(at: start + 1.5), 90, accuracy: 1e-9, "a quarter turn in 1.5 s")
        XCTAssertEqual(SignInIntro.haloAngle(at: start + 3), 180, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.haloAngle(at: start + 4.5), 270, accuracy: 1e-9)
        XCTAssertEqual(apart(SignInIntro.haloAngle(at: start + 6), 0), 0, accuracy: 1e-9, "one turn in 6 s, then again")
        XCTAssertEqual(SignInIntro.haloAngle(at: start + 7.5), 90, accuracy: 1e-9)
        XCTAssertEqual(SignInIntro.haloAngle(at: start + 600 * 6 + 1.5), 90, accuracy: 1e-6, "and an hour later")

        var previous = SignInIntro.haloAngle(at: start)
        for step in 1...1500 {
            let angle = SignInIntro.haloAngle(at: start + Double(step) / 100)
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThan(angle, 360, "it wraps (\(step) hundredths of a second)")
            XCTAssertEqual(apart(angle, previous + 0.6), 0, accuracy: 1e-6, "at one speed: 0.6 degrees in 10 ms, clockwise")
            previous = angle
        }
    }

    func testTheHaloBreathesInTheRangeOfItsAppearance() {
        XCTAssertEqual(SignInIntro.haloRange(dark: false).low, 0.25)
        XCTAssertEqual(SignInIntro.haloRange(dark: false).high, 0.45)
        XCTAssertEqual(SignInIntro.haloRange(dark: true).low, 0.35, "on a dark screen the halo is stronger")
        XCTAssertEqual(SignInIntro.haloRange(dark: true).high, 0.60)

        for dark in [false, true] {
            let range = SignInIntro.haloRange(dark: dark)
            XCTAssertEqual(SignInIntro.haloOpacity(at: 0, dark: dark), 0)
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.chevronSettle, dark: dark), 0, "no halo while the chevrons slide")
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.end, dark: dark), range.low, accuracy: 1e-9)
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.end + 1, dark: dark), (range.low + range.high) / 2, accuracy: 1e-9)
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.end + 2, dark: dark), range.high, accuracy: 1e-9)
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.end + 4, dark: dark), range.low, accuracy: 1e-9, "one breath is 4 s")
            XCTAssertEqual(SignInIntro.haloOpacity(at: SignInIntro.end + 4 * 500 + 2, dark: dark), range.high, accuracy: 1e-6)

            var previous = 0.0
            for step in 0...180 {
                let opacity = SignInIntro.haloOpacity(at: Double(step) / 200, dark: dark)
                XCTAssertGreaterThanOrEqual(opacity, previous - 1e-9, "it only fades in until the intro is over (dark: \(dark))")
                XCTAssertLessThanOrEqual(opacity, range.low + 1e-9)
                previous = opacity
            }
            for step in 0...160 {
                let opacity = SignInIntro.haloOpacity(at: SignInIntro.end + Double(step) / 20, dark: dark)
                XCTAssertGreaterThanOrEqual(opacity, range.low - 1e-9)
                XCTAssertLessThanOrEqual(opacity, range.high + 1e-9)
            }
        }
    }

    // MARK: - When each part is drawn again

    func testTheLogoIsDrawnEveryFrameUntilTheIntroIsOverThenAtEachTurnOfTheBlink() throws {
        let ticks = SignInLogoTicks()
        XCTAssertEqual(ticks.next(after: -3), 0, "nothing moves before the start")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0)), 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0.895)), SignInIntro.end, accuracy: 1e-9, "the last frame is the end itself")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: SignInIntro.end)), SignInIntro.end + 0.53, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: SignInIntro.end + 0.53)), SignInIntro.end + 1.06, accuracy: 1e-9)

        var time = -1.0
        var frames = 0
        while let next = ticks.next(after: time), next <= SignInIntro.end + 1e-9 {
            XCTAssertGreaterThan(next, time)
            time = next
            frames += 1
        }
        XCTAssertEqual(frames, 55, "the start, then 54 frames of a sixtieth of a second up to 0.9 s")
        var on = SignInIntro.underscoreOpacity(at: time)
        XCTAssertEqual(on, 1)
        for _ in 0..<8 {
            let next = try XCTUnwrap(ticks.next(after: time))
            XCTAssertEqual(next - time, CursorBlink.half, accuracy: 1e-6)
            XCTAssertNotEqual(SignInIntro.underscoreOpacity(at: next), on, "each tick after the intro turns the underscore")
            on = SignInIntro.underscoreOpacity(at: next)
            time = next
        }
    }

    func testTheCursorStaysOnWhileLettersComeAndGoAndBlinksWhileTheLineRests() {
        let held = 0.028 * 5
        XCTAssertTrue(schedule.cursorIsOn(at: -0.4), "before the first letter the cursor waits, on")
        XCTAssertTrue(schedule.cursorIsOn(at: 0.05), "typing")
        XCTAssertTrue(schedule.cursorIsOn(at: held + 0.1))
        XCTAssertFalse(schedule.cursorIsOn(at: held + 0.6), "530 ms into the hold it is off")
        XCTAssertTrue(schedule.cursorIsOn(at: held + 1.1), "and on again 530 ms later")
        XCTAssertFalse(schedule.cursorIsOn(at: held + 1.7))
        XCTAssertTrue(schedule.cursorIsOn(at: held + 2.4 + 0.02), "erasing")
        XCTAssertTrue(schedule.cursorIsOn(at: held + 2.4 + 0.06 + 0.1), "the pause is shorter than half a blink")
        XCTAssertTrue(TypewriterSchedule(lines: []).cursorIsOn(at: 3))
    }

    func testTheTypedLineIsDrawnAtEachLetterAndAtEachTurnOfTheBlinkWhileItRests() throws {
        let ticks = TypewriterTicks(schedule: schedule)
        let held = 0.028 * 5
        XCTAssertEqual(ticks.next(after: -0.4), 0, "the first letter")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0)), 0.028, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0.028 * 4)), held, accuracy: 1e-9, "the hold begins")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: held)), held + 0.53, accuracy: 1e-9, "the cursor goes off")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: held + 0.53)), held + 1.06, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: held + 2.12)), held + 2.4, accuracy: 1e-9, "erasing comes before the next turn")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: held + 2.4)), held + 2.4 + 0.012, accuracy: 1e-9)
        XCTAssertNil(TypewriterTicks(schedule: TypewriterSchedule(lines: [])).next(after: 0), "nothing to type: never drawn again")

        // Every tick is later than the one before, and one of the three it is for really changes.
        var time = -0.1
        var count = 0
        while time < schedule.cycle {
            let next = try XCTUnwrap(ticks.next(after: time))
            XCTAssertGreaterThan(next, time)
            let before = schedule.frame(at: time)
            let after = schedule.frame(at: next)
            XCTAssertTrue(
                before.text != after.text || before.phase != after.phase || before.line != after.line
                    || schedule.cursorIsOn(at: time) != schedule.cursorIsOn(at: next),
                "nothing changes at \(next) (after \(time))")
            time = next
            count += 1
        }
        // The start, 20 changes of text or phase in a cycle, and 4 turns of the cursor in each of the two holds.
        XCTAssertEqual(count, 1 + 20 + 2 * 4)
    }

    func testAGuideRowFadesInAndComesUpOverAQuarterOfASecondThenStays() throws {
        XCTAssertEqual(SignInGuideView.progress(row: 0, at: 0), 0)
        XCTAssertEqual(SignInGuideView.progress(row: 0, at: SignInIntro.chevronSettle), 0)
        XCTAssertEqual(SignInGuideView.progress(row: 0, at: SignInIntro.chevronSettle + 0.125), 0.75, accuracy: 1e-9, "it eases out")
        XCTAssertEqual(SignInGuideView.progress(row: 0, at: SignInIntro.chevronSettle + 0.25), 1, accuracy: 1e-9)
        XCTAssertEqual(SignInGuideView.progress(row: 2, at: 0.75), 0, "the third row starts at 0.76 s")
        XCTAssertEqual(SignInGuideView.progress(row: 2, at: 5), 1)

        let ticks = SignInGuideTicks()
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0)), SignInIntro.chevronSettle, accuracy: 1e-9, "nothing to draw until the logo settles")
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 0.6)), 0.6 + 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ticks.next(after: 1.0)), 1.01, accuracy: 1e-9, "the last frame is the third row in place")
        XCTAssertNil(ticks.next(after: 1.01), "then the guide is never drawn again")
    }

    func testATimelineIsDrawnWhenItAppearsThenAtEachTickAndEndsWithThem() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let timeline = SignInIntroTimeline(start: start, ticks: SignInGuideTicks())

        var entries = timeline.entries(from: start.addingTimeInterval(-2), mode: .normal)
        XCTAssertEqual(entries.next(), start.addingTimeInterval(-2), "the moment it is asked for")
        XCTAssertEqual(try XCTUnwrap(entries.next()).timeIntervalSince(start), 0.6, accuracy: 1e-6)
        var last = start
        var count = 2
        while let date = entries.next() {
            XCTAssertGreaterThan(date, last)
            last = date
            count += 1
            if count > 100 { return XCTFail("the guide's timeline should end") }
        }
        XCTAssertEqual(last.timeIntervalSince(start), 1.01, accuracy: 1e-6)
        XCTAssertEqual(count, 2 + 25, "0.41 s of frames after the first")

        var late = timeline.entries(from: start.addingTimeInterval(30), mode: .normal)
        XCTAssertEqual(late.next(), start.addingTimeInterval(30), "a guide already in place is drawn once")
        XCTAssertNil(late.next())

        // The blink never ends, and a tick keeps its place after hours on the screen.
        var blink = SignInIntroTimeline(start: start, ticks: SignInLogoTicks()).entries(from: start.addingTimeInterval(7200), mode: .normal)
        _ = blink.next()
        let first = try XCTUnwrap(blink.next())
        let second = try XCTUnwrap(blink.next())
        XCTAssertEqual(second.timeIntervalSince(first), CursorBlink.half, accuracy: 1e-6)
    }

    // MARK: - The mark

    func testTheMarkIsTheDrawingOfTheAppIcon() {
        XCTAssertEqual(SignInLogoMark.prompt, [CGPoint(x: 128, y: 122), CGPoint(x: 222, y: 234), CGPoint(x: 128, y: 346)])
        XCTAssertEqual(SignInLogoMark.phone, [CGPoint(x: 384, y: 122), CGPoint(x: 290, y: 234), CGPoint(x: 384, y: 346)])
        XCTAssertEqual(SignInLogoMark.stroke, 54)
        XCTAssertEqual(SignInLogoMark.cursor, CGRect(x: 300, y: 398, width: 84, height: 26))
        XCTAssertEqual(SignInLogoMark.cornerRadius, 114)
        XCTAssertEqual(SignInLogoMark.side, 512)
        // A chevron's tip with half its stroke: the furthest it reaches into the square from its own edge.
        let reach = (SignInLogoMark.prompt[1].x + SignInLogoMark.stroke / 2) / SignInLogoMark.side
        XCTAssertGreaterThan(SignInIntro.chevronStart, Double(reach), "it starts wholly outside")
        XCTAssertEqual(SignInLogoMark.side - SignInLogoMark.phone[1].x + SignInLogoMark.stroke / 2, SignInLogoMark.prompt[1].x + SignInLogoMark.stroke / 2)
    }

    func testTheHaloHasTheBrandsFiveSoftColoursAndClosesOnTheFirst() {
        XCTAssertEqual(SignInLogoMark.haloPalette, [0x4AF2A1, 0x60A5FA, 0xA78BFA, 0xF472B6, 0xFBBF24, 0x4AF2A1], "mint, blue, violet, pink, amber, mint")
        XCTAssertEqual(SignInLogoMark.haloPalette.first, SignInLogoMark.haloPalette.last, "the turn closes without a seam")
        XCTAssertEqual(SignInLogoMark.haloColors.count, SignInLogoMark.haloPalette.count)

        // The halo keeps the reach of the mint glow it replaces (the square blurred by 0.16 of its side, seen some 25
        // points around a 96-point logo), as far as the title allows: the title's letters begin 24 points under the
        // logo, and the halo is gone before them.
        let reach = (SignInLogoMark.haloExtent - 1) / 2 * 96
        XCTAssertGreaterThanOrEqual(reach, 20, "the halo reaches about as far round a 96-point logo as the mint glow did")
        XCTAssertLessThanOrEqual(reach, 23, "and ends before the title's letters, 24 points under the logo")

        // The colours turn in a square; the halo is cut from it. Its farthest point is on the square's diagonal: the
        // corner of its shape (the logo's corner, a little larger) and the fade beyond. The inscribed circle of the
        // square of colours must reach it, or a turn would cut the halo's corners.
        let half = 0.5 + SignInLogoMark.haloSpread
        let corner = SignInLogoMark.cornerRadius / SignInLogoMark.side + SignInLogoMark.haloSpread
        let farthest = (half - corner) * 2.squareRoot() + corner + 2.4 * SignInLogoMark.haloSoftness
        XCTAssertGreaterThan(SignInLogoMark.haloField / 2, farthest, "the turning colours cover the halo to its corners")
    }

    func testAGradientRunsAcrossItsShapeAsInTheDrawing() {
        // The drawing gives the mint gradient in the chevron's own box, corner to corner. The box is 94 by 224, so
        // the colours do not run along its diagonal: the tip is three quarters of the way, the lower end half way.
        let box = SignInLogoMark.box(of: SignInLogoMark.prompt)
        XCTAssertEqual(box, CGRect(x: 128, y: 122, width: 94, height: 224))
        let axis = SignInLogoMark.gradientAxis(in: box, from: .topLeading, to: .bottomTrailing)
        func part(_ point: CGPoint) -> Double {
            let (dx, dy) = (axis.end.x - axis.start.x, axis.end.y - axis.start.y)
            return Double(((point.x - axis.start.x) * dx + (point.y - axis.start.y) * dy) / (dx * dx + dy * dy))
        }
        XCTAssertEqual(part(CGPoint(x: 128, y: 122)), 0, accuracy: 1e-9)
        XCTAssertEqual(part(CGPoint(x: 222, y: 346)), 1, accuracy: 1e-9)
        XCTAssertEqual(part(CGPoint(x: 222, y: 234)), 0.75, accuracy: 1e-9)
        XCTAssertEqual(part(CGPoint(x: 128, y: 346)), 0.5, accuracy: 1e-9)

        let mirrored = SignInLogoMark.gradientAxis(
            in: SignInLogoMark.box(of: SignInLogoMark.phone), from: .topTrailing, to: .bottomLeading)
        XCTAssertEqual(mirrored.start, CGPoint(x: 384, y: 122))
        XCTAssertEqual(mirrored.end.x, SignInLogoMark.side - axis.end.x, accuracy: 1e-9, "the lilac chevron mirrors the mint one")
        XCTAssertEqual(mirrored.end.y, axis.end.y, accuracy: 1e-9)

        let square = SignInLogoMark.gradientAxis(in: CGRect(x: 10, y: 20, width: 30, height: 30), from: .topLeading, to: .bottomTrailing)
        XCTAssertEqual(square.end.x, 40, accuracy: 1e-9, "in a square box it is the diagonal")
        XCTAssertEqual(square.end.y, 50, accuracy: 1e-9)
    }
}

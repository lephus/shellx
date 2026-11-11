import ShellXAppCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The sign-in screen with its intro, drawn: on a small phone, on its side and in large type; the logo at rest
/// against the app's own logo; and the intro as it runs (before it starts, while a tagline is typed, after it has
/// settled), where the buttons must be in place from the first frame, the cursor must follow the typed letters,
/// and the halo must be a ring of colours that turns and stays in the room around the logo.
///
/// A test run draws the intro still. A frame of the running intro is drawn for a given moment (`motion: .at(…)`),
/// and the typed line for a given frame of the typewriter: no test here depends on when or how fast it runs. The
/// one test that lets the parts read the clock places their start an hour away, where what they show no longer
/// changes.
@MainActor
final class SignInRenderTests: XCTestCase {
    /// iPhone SE (3rd generation), portrait: 375 x 667 points, 20 points of status bar.
    private static let se = (size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
    /// iPhone 16 on its side: 852 x 393 points, the island on one side, the home indicator below.
    private static let landscape = (
        size: CGSize(width: 852, height: 393), safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
    )
    /// iPhone 16 Pro Max on its side: 956 x 440 points.
    private static let landscapeMax = (
        size: CGSize(width: 956, height: 440), safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
    )

    private func signIn(motion: SignInIntroMotion? = nil, expired: Bool = false, error: SignInError? = nil) -> SignInView {
        SignInView(coordinator: .preview(), expired: expired, startDemo: {}, initialError: error, motion: motion)
    }

    /// iPhone 16, upright: 393 x 852 points, the island above, the home indicator below.
    private static let portrait = (size: SnapshotWriter.size, safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))

    /// Moments of the intro, in seconds after its start.
    private enum Moment {
        /// The start: the chevrons are outside the square, nothing is typed, no step shows.
        static let start: TimeInterval = 0
        /// The 14th letter of the first tagline has just been typed; the cursor is on, as always while typing.
        static let typing = TypedTaglineView.startDelay + 13.5 * 0.028
        /// The underscore is on again after two blinks and the halo is near the top of its first breath.
        static let glowing = SignInIntro.end + 4 * CursorBlink.half
        /// The underscore is on again after four blinks and the halo near its weakest, at the start of its second breath.
        static let faint = SignInIntro.end + 8 * CursorBlink.half
        /// The halo at the very top of its breath.
        static let brightest = SignInIntro.end + SignInIntro.haloBreath / 2
        /// One second into the halo's first breath: half way up.
        static let halo = SignInIntro.end + 1

        /// The first tagline (`letters` long) is whole and has been held for 0.2 s: its cursor is still on.
        static func held(letters: Int) -> TimeInterval { TypedTaglineView.startDelay + Double(letters) * 0.028 + 0.2 }
    }

    private func bitmaps(_ images: [UIImage], file: StaticString = #filePath, line: UInt = #line) throws -> [Bitmap] {
        XCTAssertEqual(images.count, 2, file: file, line: line)
        return try images.map { try XCTUnwrap(Bitmap($0), file: file, line: line) }
    }

    // MARK: - Sizes

    func testASmallPhoneShowsTheWholeScreenWithoutScrolling() throws {
        let images = try SnapshotWriter().write(signIn(), name: "signin-se", size: Self.se.size, safeArea: Self.se.safeArea)
        let bitmaps = try self.bitmaps(images)
        for bitmap in bitmaps {
            XCTAssertEqual(bitmap.pointSize, Self.se.size)
            let buttons = try XCTUnwrap(bitmap.firstRowWithAWhiteRun(), "the Google button is on the screen")
            XCTAssertLessThan(buttons, 667 - 44 - 12 - 44 - 12 - 44, "and under it the Apple button and the demo link fit")
            XCTAssertTrue(bitmap.isPlain(fromRow: 667 - 12), "nothing is cut at the bottom edge")
        }
        // In the light appearance the logo's dark square stands out from the background.
        XCTAssertGreaterThan(bitmaps[0].darkSquareSide(), 90, "the logo keeps its 96 points in 647 points of height")
        XCTAssertLessThan(bitmaps[0].darkSquareSide(), 100)
    }

    func testASmallPhoneWithEveryMessageStillShowsItsButtons() throws {
        let images = try SnapshotWriter().write(
            signIn(expired: true, error: .switchFromSignedInDevice), name: "signin-se-messages", size: Self.se.size,
            safeArea: Self.se.safeArea)
        for bitmap in try bitmaps(images) {
            XCTAssertNotNil(bitmap.firstRowWithAWhiteRun(), "the messages push the buttons down, never off the first screen")
        }
    }

    func testOnItsSideTheButtonsAreBesideTheLogo() throws {
        let images = try SnapshotWriter().write(
            signIn(), name: "signin-landscape", size: Self.landscape.size, safeArea: Self.landscape.safeArea)
        let bitmaps = try self.bitmaps(images)
        for bitmap in bitmaps {
            XCTAssertEqual(bitmap.pointSize, Self.landscape.size)
            let buttons = try XCTUnwrap(bitmap.firstRowWithAWhiteRun())
            let run = bitmap.longestWhiteRun(row: buttons)
            XCTAssertGreaterThan(run.lowerBound, 852 / 2, "the buttons are in the right half")
            XCTAssertTrue(bitmap.isPlain(fromRow: 393 - 21), "everything fits above the home indicator")
        }
        // In the light appearance the logo's dark square stands out from the background.
        let logo = bitmaps[0].darkSquareSide()
        XCTAssertGreaterThan(logo, 66, "the logo is 72 points on its side")
        XCTAssertLessThan(logo, 76)
    }

    func testALargePhoneOnItsSideAlsoShowsTheSteps() throws {
        let narrow = try bitmaps(SnapshotWriter().write(
            signIn(), name: "signin-landscape", size: Self.landscape.size, safeArea: Self.landscape.safeArea))
        let wide = try bitmaps(SnapshotWriter().write(
            signIn(), name: "signin-landscape-max", size: Self.landscapeMax.size, safeArea: Self.landscapeMax.safeArea))
        for (narrow, wide) in zip(narrow, wide) {
            // 372 points of height: no steps, the buttons start at the top of their column. 419: under the steps.
            let high = try XCTUnwrap(narrow.firstRowWithAWhiteRun())
            let low = try XCTUnwrap(wide.firstRowWithAWhiteRun())
            XCTAssertLessThan(high, 40)
            XCTAssertGreaterThan(low, high + 80, "three rows of steps stand over the buttons")
            XCTAssertTrue(wide.isPlain(fromRow: 440 - 21))
        }
    }

    func testLargeTypeRenders() throws {
        let large = signIn().dynamicTypeSize(.xxxLarge)
        let images = try SnapshotWriter().write(large, name: "signin-large-type")
        let plain = try SnapshotWriter().write(signIn(), name: "signin-intro")
        XCTAssertNotEqual(images.first?.pngData(), plain.first?.pngData())
        _ = try SnapshotWriter().write(large, name: "signin-se-large-type", size: Self.se.size, safeArea: Self.se.safeArea)
        _ = try SnapshotWriter().write(
            signIn().dynamicTypeSize(.accessibility2), name: "signin-accessibility-type")
    }

    // MARK: - The logo

    private func stage(_ logo: some View) -> some View {
        logo
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }

    func testTheLogoAtRestIsTheAppLogo() throws {
        let side: CGFloat = 240
        let drawn = try bitmaps(SnapshotWriter().write(stage(SignInLogoView(size: side, motion: .still)), name: "signin-logo"))
        let asset = try bitmaps(SnapshotWriter().write(
            stage(Image("Logo").resizable().frame(width: side, height: side)), name: "signin-logo-asset"))
        for (drawn, asset) in zip(drawn, asset) {
            let difference = drawn.difference(to: asset)
            // Measured: a mean of 0.76 and 3 pixels in 100,000 far off, all on the edges, where the two are smoothed
            // differently.
            XCTAssertLessThan(difference.mean, 1.2, "the mark drawn in code is the Logo asset (mean difference per channel, of 255)")
            XCTAssertLessThan(difference.far, 0.001, "and no part of it is somewhere else (share of its pixels more than 40 away)")
        }
    }

    private func logo(_ motion: SignInIntroMotion, start: Date = Date(), name: String) throws -> [Bitmap] {
        try bitmaps(SnapshotWriter().write(stage(SignInLogoView(size: 240, motion: motion, start: start)), name: name))
    }

    /// The pixels the mark lights up: the chevrons and the underscore, mint on the left, near white on the right.
    private static let bright: (Bitmap.Colour) -> Bool = { $0.brightest > 200 }
    /// The pixels that are well lit on the black stage: the mark, and the halo where it is strong.
    private static let lit: (Bitmap.Colour) -> Bool = { $0.brightest > 60 }

    func testTheChevronsAreOutsideTheSquareAtTheStartAndInPlaceOnceSettled() throws {
        let rest = try logo(.still, name: "signin-logo")
        let before = try logo(.at(Moment.start), name: "signin-logo-before")
        let glowing = try logo(.at(Moment.glowing), name: "signin-logo-after")
        let faint = try logo(.at(Moment.faint), name: "signin-logo-after-faint")
        for index in rest.indices {
            let scale = rest[index].scale
            // Together the chevrons and the underscore cover some 8,000 square points of a 240-point logo.
            let mark = rest[index].count(where: Self.bright)
            XCTAssertGreaterThan(mark, 6000 * scale * scale, "at rest the chevrons are drawn")
            XCTAssertEqual(before[index].count(where: Self.bright), 0, "at the start the square is empty")
            // On the black stage, what is lit is the 240-point square and, once it is there, the halo around it,
            // a third wider.
            let square = try XCTUnwrap(before[index].litBox())
            XCTAssertEqual(square.width, CGFloat(240 * scale), accuracy: CGFloat(2 * scale), "and there is no halo yet")
            XCTAssertEqual(square.height, CGFloat(240 * scale), accuracy: CGFloat(2 * scale))
            for settled in [glowing[index], faint[index]] {
                XCTAssertEqual(
                    settled.count(where: Self.bright), mark, accuracy: 4 * scale * scale,
                    "settled, with the underscore on, the mark is the mark at rest")
                let halo = try XCTUnwrap(settled.litBox())
                XCTAssertGreaterThan(halo.width, CGFloat((240 + 30) * scale), "and the halo lies around the square, which the still logo does not have")
                XCTAssertLessThanOrEqual(halo.width, CGFloat(240 * scale) * SignInLogoMark.haloExtent + CGFloat(scale), "no wider than it is made")
                XCTAssertEqual(halo.midX, square.midX, accuracy: CGFloat(2 * scale), "around the logo's centre")
                XCTAssertEqual(halo.midY, square.midY, accuracy: CGFloat(2 * scale))
            }
            XCTAssertGreaterThan(
                glowing[index].count(where: Self.lit), faint[index].count(where: Self.lit) + 800 * scale * scale,
                "the halo breathes: more of it is strong near the top of a breath")
        }
    }

    func testTheHaloIsARingOfColoursThatTurnsClockwise() throws {
        // The 240-point logo on the black stage, one second into the halo's breath and 1.5 s later: a quarter turn.
        // Four points on the halo, 5 points outside the middle of each side of the square: top, right, bottom, left.
        let rest = try logo(.still, name: "signin-logo")
        let first = try logo(.at(Moment.halo), name: "signin-logo-halo")
        let second = try logo(.at(Moment.halo + 1.5), name: "signin-logo-halo-later")
        var strength: [Int] = []
        for index in rest.indices {
            let scale = rest[index].scale
            let square = try XCTUnwrap(rest[index].litBox())
            XCTAssertEqual(square.width, CGFloat(240 * scale), accuracy: CGFloat(2 * scale), "still, only the square is lit: no halo")
            XCTAssertEqual(square.height, CGFloat(240 * scale), accuracy: CGFloat(2 * scale))

            let reach = Int(square.width) / 2 + 5 * scale
            let (x, y) = (Int(square.midX), Int(square.midY))
            let points = [(x, y - reach), (x + reach, y), (x, y + reach), (x - reach, y)]
            let hues = try points.map { try XCTUnwrap(first[index].mean(x: $0.0, y: $0.1, radius: scale).hue, "the halo is coloured at \($0)") }
            let later = try points.map { try XCTUnwrap(second[index].mean(x: $0.0, y: $0.1, radius: scale).hue, "the halo is coloured at \($0)") }
            // Hues more than 40 degrees from each other count as different colours. Measured: 305, 40, 157 and 230
            // degrees (pink, amber, mint, blue), then 228, 305, 40 and 156 a quarter turn later.
            var different: [Double] = []
            for hue in hues where different.allSatisfy({ Bitmap.Colour.apart($0, hue) > 40 }) { different.append(hue) }
            XCTAssertGreaterThanOrEqual(different.count, 3, "at least three clearly different colours around the logo: hues \(hues)")

            XCTAssertGreaterThan(Bitmap.Colour.apart(later[0], hues[0]), 30, "1.5 s later the colour at the top is another: \(hues) then \(later)")
            for side in 0..<4 {
                XCTAssertLessThan(
                    Bitmap.Colour.apart(later[(side + 1) % 4], hues[side]), 20,
                    "the colours travel clockwise: what was at one side is at the next a quarter turn later: \(hues) then \(later)")
            }
            // At the top of a breath (the second frame is 2.5 s into it, the top is at 2 s), how lit the halo is.
            strength.append(points.map { second[index].mean(x: $0.0, y: $0.1, radius: scale).brightest }.reduce(0, +))
        }
        // 0.56 against 0.42 at that moment: a third more (measured: 334 against 247).
        XCTAssertGreaterThan(
            strength[1] * 100, strength[0] * 115, "in the dark appearance the halo is stronger than in the light one: \(strength)")
    }

    func testOnTheClockThePartsAreAsAtTheStartBeforeItAndAtRestLongAfter() throws {
        // The running intro reads the clock. With its start an hour ahead it shows what it shows at the start, and
        // with its start an hour back, what no longer changes: the chevrons in place, the three steps. Neither
        // depends on when the frame is drawn.
        let ahead = Date().addingTimeInterval(3600)
        let back = Date().addingTimeInterval(-3600)

        XCTAssertEqual(
            try SnapshotWriter().write(stage(SignInLogoView(size: 240, motion: .animated, start: ahead)), name: "signin-logo-clock-before")
                .map { $0.pngData() },
            try SnapshotWriter().write(stage(SignInLogoView(size: 240, motion: .at(Moment.start))), name: "signin-logo-before").map { $0.pngData() },
            "the logo before its start")
        let rest = try logo(.still, name: "signin-logo")
        let running = try logo(.animated, start: back, name: "signin-logo-clock-after")
        for index in rest.indices {
            let scale = rest[index].scale
            let mark = rest[index].count(where: Self.bright)
            let settled = running[index].count(where: Self.bright)
            XCTAssertGreaterThan(settled, mark * 9 / 10, "the chevrons are in place (the underscore may be off)")
            XCTAssertLessThanOrEqual(settled, mark + 4 * scale * scale, "and nothing else is lit")
            XCTAssertGreaterThan(
                try XCTUnwrap(running[index].litBox()).width, CGFloat((240 + 30) * scale),
                "with the halo around the square, at any point of its breath")
        }

        func steps(_ motion: SignInIntroMotion, start: Date = Date(), name: String) throws -> [Data?] {
            let guide = SignInGuideView(motion: motion, start: start)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.appBackground)
            return try SnapshotWriter().write(guide, name: name, size: CGSize(width: 393, height: 200), safeArea: EdgeInsets())
                .map { $0.pngData() }
        }
        XCTAssertEqual(try steps(.animated, start: ahead, name: "signin-guide-clock-before"), try steps(.at(Moment.start), name: "signin-guide-before"))
        XCTAssertEqual(try steps(.animated, start: back, name: "signin-guide-clock-after"), try steps(.still, name: "signin-guide"))
        XCTAssertNotEqual(try steps(.at(Moment.start), name: "signin-guide-before"), try steps(.still, name: "signin-guide"))

        func tagline(_ motion: SignInIntroMotion, start: Date = Date(), name: String) throws -> [Data?] {
            let line = TypedTaglineView(motion: motion, start: start)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.appBackground)
            return try SnapshotWriter().write(line, name: name, size: CGSize(width: 393, height: 120), safeArea: EdgeInsets())
                .map { $0.pngData() }
        }
        XCTAssertEqual(
            try tagline(.animated, start: ahead, name: "signin-tagline-clock-before"), try tagline(.at(Moment.start), name: "signin-tagline-before"),
            "the tagline before its start: no letter, the cursor waiting")
        XCTAssertNotEqual(try tagline(.at(Moment.start), name: "signin-tagline-before"), try tagline(.still, name: "signin-tagline-still"))
    }

    // MARK: - The intro and the buttons

    func testATestRunDrawsTheIntroStill() throws {
        let decided = try SnapshotWriter().write(signIn(), name: "signin-intro")
        let still = try SnapshotWriter().write(signIn(motion: .still), name: "signin-intro")
        XCTAssertEqual(decided.map { $0.pngData() }, still.map { $0.pngData() })
    }

    func testTheButtonsAreInPlaceBeforeTheIntroHasStarted() throws {
        let still = try bitmaps(SnapshotWriter().write(signIn(motion: .still), name: "signin-intro"))
        let before = try bitmaps(SnapshotWriter().write(signIn(motion: .at(Moment.start)), name: "signin-intro-before"))
        for (still, before) in zip(still, before) {
            let buttons = try XCTUnwrap(still.firstRowWithAWhiteRun())
            XCTAssertEqual(before.firstRowWithAWhiteRun(), buttons, "the buttons are where they will stay, from the first frame")
            XCTAssertEqual(
                before.differingRows(to: still, fromRow: buttons - 8), 0,
                "and from there down the screen is already what it will be: Google, Apple, the demo link")
            XCTAssertGreaterThan(
                before.differingRows(to: still, fromRow: 0), 100, "above them the intro has not begun: no chevrons, no tagline, no steps")
        }
    }

    func testWhileATaglineIsTypedNothingUnderItMoves() throws {
        let still = try bitmaps(SnapshotWriter().write(signIn(motion: .still), name: "signin-intro"))
        let typing = try bitmaps(SnapshotWriter().write(signIn(motion: .at(Moment.typing)), name: "signin-intro-typing"))
        let held = try bitmaps(SnapshotWriter().write(
            signIn(motion: .at(Moment.held(letters: TypedTaglineView.lines()[0].count))), name: "signin-intro-settled"))
        for (index, style) in [UIUserInterfaceStyle.light, .dark].enumerated() {
            let buttons = try XCTUnwrap(still[index].firstRowWithAWhiteRun())
            // The still screen has the theme's green in the steps' numbers only; a typed line adds its cursor, a
            // block of it some 4 by 27 points.
            let green = try XCTUnwrap(Bitmap.Colour(UIColor(named: "StatusDone"), style: style))
            let scale = still[index].scale
            let numbers = still[index].count { $0.distance(to: green) < 24 }
            for (frame, what) in [(typing[index], "while 14 letters are typed"), (held[index], "while the whole line is held")] {
                XCTAssertEqual(frame.firstRowWithAWhiteRun(), buttons, "the buttons stay where they are \(what)")
                XCTAssertEqual(
                    frame.differingRows(to: still[index], fromRow: buttons - 8), 0, "and so does everything under them \(what)")
                let cursor = frame.count { $0.distance(to: green) < 24 } - numbers
                XCTAssertGreaterThan(cursor, 60 * scale * scale, "the cursor is drawn \(what)")
                XCTAssertLessThan(cursor, 200 * scale * scale, "and it is one small block \(what)")
            }
        }
    }

    // MARK: - The typed line

    func testTheLineKeepsTwoRowsTheTallestTaglineAndRoomForTheCursor() throws {
        let lines = try (1...3).map { try Self.tagline($0, language: "en") }
        let view = TypedLineView()
        let font = TypedLineView.font(.large)
        view.show(TypedLineView.Content(lines: lines, line: lines[0], typed: lines[0]), font: font, dark: false)
        XCTAssertGreaterThanOrEqual(view.cursorWidth, 3)
        XCTAssertLessThanOrEqual(view.cursorWidth, 6, "a block about as wide as a terminal's")

        // A one-row tagline in a wide view: two rows all the same. In a narrow one: the rows the longest needs.
        let wide = view.fittingSize(width: 361)
        XCTAssertEqual(wide.width, 361)
        XCTAssertEqual(wide.height, (2 * view.rowHeight).rounded(.up))
        let narrow = view.fittingSize(width: 150)
        XCTAssertGreaterThanOrEqual(narrow.height, 3 * view.rowHeight, "41 letters need three rows or more in 150 points")
        for line in lines {
            view.show(TypedLineView.Content(lines: lines, line: line, typed: line), font: font, dark: false)
            XCTAssertEqual(view.fittingSize(width: 150), narrow, "the height does not depend on the line shown")
        }

        // Whatever the width, the cursor after the last letter is inside the view, and inside its height.
        for width in stride(from: CGFloat(120), through: 393, by: 1) {
            let size = view.fittingSize(width: width)
            for line in lines {
                view.show(TypedLineView.Content(lines: lines, line: line, typed: line), font: font, dark: false)
                let cursor = view.cursorRect(in: width)
                XCTAssertLessThanOrEqual(cursor.maxX, width + 0.01, "\(line) in \(width) points")
                XCTAssertLessThanOrEqual(cursor.maxY, size.height + 0.01, "\(line) in \(width) points")
                XCTAssertGreaterThan(cursor.minX, 0, "the cursor is after the last letter (\(line) in \(width) points)")
            }
        }

        // With nothing typed the cursor is at the start; with no line at all, too.
        view.show(TypedLineView.Content(lines: lines, line: lines[1], typed: ""), font: font, dark: false)
        XCTAssertEqual(view.cursorRect(in: 361).origin, .zero)
        view.show(TypedLineView.Content(), font: font, dark: false)
        XCTAssertEqual(view.cursorRect(in: 361).origin, .zero)
        XCTAssertEqual(view.fittingSize(width: 361).height, (2 * view.rowHeight).rounded(.up))
    }

    func testALineBreaksOnceWhateverIsTyped() throws {
        // The second English tagline in the 361 points of an iPhone 16: "doing," would fit on the first row, and is
        // taken down so that "anywhere." does not stand alone, as a label does. The rows are the whole line's, with
        // one letter typed or all of them.
        let line = try Self.tagline(2, language: "en")
        let view = TypedLineView()
        var rows: [[String]] = []
        for typed in [0, 1, 25, 31, 32, 36, 41] {
            view.show(
                TypedLineView.Content(lines: [line], line: line, typed: String(line.prefix(typed))), font: TypedLineView.font(.large),
                dark: false)
            rows.append(view.rowRanges(in: 361).map { (line as NSString).substring(with: $0) })
        }
        XCTAssertEqual(rows.first, ["See what your agents are ", "doing, anywhere."])
        XCTAssertEqual(Set(rows).count, 1, "the same rows at every moment: \(rows)")
    }

    func testTheCursorShowsAfterTheLastLetterOfAHeldLine() throws {
        // A whole line with the cursor on, in a frame no wider than the view asks for: the cursor is drawn whole
        // after the last letter, and the letters are where they are without it.
        let line = "Control your Mac"
        func stage(cursorIsOn: Bool) -> some View {
            TypedLine(lines: [line], line: line, typed: line, cursorIsOn: cursorIsOn)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
        let size = CGSize(width: 393, height: 140)
        let on = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: true), name: "signin-tagline-held", size: size, safeArea: EdgeInsets()))
        let off = try bitmaps(
            SnapshotWriter().write(stage(cursorIsOn: false), name: "signin-tagline-held-off", size: size, safeArea: EdgeInsets()))
        for (index, style) in [UIUserInterfaceStyle.light, .dark].enumerated() {
            let green = try XCTUnwrap(Bitmap.Colour(UIColor(named: "StatusDone"), style: style))
            let scale = on[index].scale
            XCTAssertEqual(off[index].count { $0.distance(to: green) < 24 }, 0, "off, the cursor leaves no trace")
            let cursor = on[index].count { $0.distance(to: green) < 24 }
            XCTAssertGreaterThan(cursor, 60 * scale * scale, "on, it is drawn after the last letter: a block some 4 by 24 points")
            XCTAssertLessThan(cursor, 200 * scale * scale)
            // The letters are where they are without the cursor: only the block differs.
            let columns = on[index].differingColumns(to: off[index])
            XCTAssertLessThan(columns.count, 8 * scale, "the two frames differ in a block a few points wide")
        }
    }

    func testTheCursorFollowsTheLettersAlsoInTheMiddleOfAWord() throws {
        // The cursor after one letter, inside a word and before the last letter, in a narrow room (220 points, where
        // the line breaks before "your"), through SwiftUI as the screen shows it. On, the cursor adds one block: on
        // the row of the last typed letters, right after the last of them.
        let line = "Control your Mac from your pocket."
        for typed in ["C", "Control your Mac from y", "Control your Mac from your pocke"] {
            let letters = try assertTheCursorFollowsTheLetters(of: line, typed: typed.count, width: 220)
            if typed.count > 30 {
                // 31 letters do not fit in 220 points: they are on two rows.
                for box in letters { XCTAssertGreaterThan(box.height, 30, "the letters are on two rows (\(typed))") }
            }
        }
    }

    func testTheCursorFollowsTheLettersOfATaglineThatBreaksBeforeItsLastTwoWords() throws {
        // "See what your agents are doing, anywhere." in the 361 points an iPhone 16 gives it: "doing," would fit on
        // the first row, and iOS takes it down so that "anywhere." does not stand alone. From "doing," to the last
        // letter but one, the cursor must stay after the letters on the second row.
        let line = try Self.tagline(2, language: "en")
        XCTAssertEqual(line, "See what your agents are doing, anywhere.")
        for typed in 31...40 {
            let letters = try assertTheCursorFollowsTheLetters(of: line, typed: typed, width: 361)
            for box in letters { XCTAssertGreaterThan(box.height, 30, "the letters are on two rows (\(typed) typed)") }
        }
    }

    func testTheCursorFollowsEveryLetterOfEveryTagline() throws {
        // Every tagline of the catalog, in English and in Vietnamese, in the widths an iPhone gives the line (343
        // points on a 375-point phone, 361 on a 393-point one), at the default text size and at the largest that is
        // not an accessibility size, after each letter typed from none to all: the letters drawn are the whole
        // line's up to the cursor, and the cursor is right after the last of them.
        for language in ["en", "vi"] {
            let lines = try (1...3).map { try Self.tagline($0, language: language) }
            for size in [DynamicTypeSize.large, .xxxLarge] {
                for width in [CGFloat(343), 361] {
                    for line in lines {
                        try assertTheDrawnCursorFollowsEveryLetter(
                            of: line, among: lines, width: width, size: size, what: "\(language), \(size), \(Int(width)) points")
                    }
                }
            }
        }
    }

    /// Tagline `number` (1 to 3) of the catalog in `language`, whatever language the test runs in.
    private static func tagline(_ number: Int, language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "no \(language).lproj in the app")
        let bundle = try XCTUnwrap(Bundle(path: path))
        let key = "signin.tagline.\(number)"
        let text = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(text, key, "\(key) is not in \(language).lproj")
        return text
    }

    /// Draws `line` through SwiftUI with its first `typed` letters and the cursor, on and off, in `width` points, and
    /// checks that the cursor is one narrow block on the row of the last typed letters, right after the last of them
    /// (at the start of the next row when they fill theirs), with no typed letter on a row under it. Returns the box
    /// around the typed letters, in points, in the light and the dark appearance.
    @discardableResult
    private func assertTheCursorFollowsTheLetters(
        of line: String, typed: Int, width: CGFloat, file: StaticString = #filePath, lineNumber: UInt = #line
    ) throws -> [CGRect] {
        func stage(cursorIsOn: Bool) -> some View {
            TypedLine(lines: [line], line: line, typed: String(line.prefix(typed)), cursorIsOn: cursorIsOn)
                .frame(width: width, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.appBackground)
        }
        let name = "signin-tagline-\(Int(width))-\(line.count)-\(typed)"
        let size = CGSize(width: 393, height: 100)
        let on = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: true), name: name, size: size, safeArea: EdgeInsets()))
        let off = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: false), name: name + "-off", size: size, safeArea: EdgeInsets()))
        var boxes: [CGRect] = []
        for index in on.indices {
            let scale = CGFloat(on[index].scale)
            let what = "\(typed) of \(line.count) letters typed, \(Int(width)) points, \(index == 0 ? "light" : "dark")"
            let letters = try XCTUnwrap(off[index].inkBox(), "the typed letters are drawn (\(what))", file: file, line: lineNumber)
            boxes.append(letters.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)))
            let cursor = try XCTUnwrap(
                on[index].differingBox(to: off[index]), "the cursor is drawn (\(what))", file: file, line: lineNumber)
            XCTAssertLessThan(cursor.height, 34 * scale, "the cursor is one row high (\(what))", file: file, line: lineNumber)
            XCTAssertLessThan(cursor.width, 8 * scale, "and a narrow block (\(what))", file: file, line: lineNumber)
            if let beside = off[index].inkBox(rows: Int(cursor.minY)...Int(cursor.maxY)) {
                XCTAssertGreaterThanOrEqual(
                    cursor.minX, beside.maxX - 2 * scale, "the cursor stands after the last letter (\(what))", file: file,
                    line: lineNumber)
                XCTAssertLessThan(cursor.minX - beside.maxX, 8 * scale, "right after it (\(what))", file: file, line: lineNumber)
            } else {
                // The typed letters fill their rows: the cursor is at the start of the next one.
                XCTAssertLessThan(
                    abs(cursor.minX - 16 * scale), 2 * scale, "the cursor is at the start of its row (\(what))", file: file,
                    line: lineNumber)
                XCTAssertNotNil(
                    off[index].inkBox(rows: 0...Int(cursor.minY) - 1), "under a row of typed letters (\(what))", file: file,
                    line: lineNumber)
            }
            XCTAssertNil(
                off[index].inkBox(rows: (Int(cursor.maxY) + 4 * Int(scale))...(off[index].height - 1)),
                "and no typed letter is on a row under it (\(what))", file: file, line: lineNumber)
        }
        return boxes
    }

    /// Draws `line` in a `TypedLineView` `width` points wide, at the text size `size`, after each letter typed, with
    /// the cursor off and on, and checks every frame: the letters drawn are those of the whole line up to the
    /// cursor, nothing is drawn after it, and the cursor is one block inside the view, right after the last letter
    /// of its row, or at the row's start under a full row.
    private func assertTheDrawnCursorFollowsEveryLetter(
        of line: String, among lines: [String], width: CGFloat, size: DynamicTypeSize, what: String,
        file: StaticString = #filePath, lineNumber: UInt = #line
    ) throws {
        let view = TypedLineView()
        let font = TypedLineView.font(size)
        func drawn(typed: Int, cursorIsOn: Bool) throws -> Bitmap {
            view.show(
                TypedLineView.Content(lines: lines, line: line, typed: String(line.prefix(typed)), cursorIsOn: cursorIsOn), font: font,
                dark: false)
            view.frame = CGRect(origin: .zero, size: view.fittingSize(width: width))
            return try XCTUnwrap(Bitmap(drawing: view), file: file, line: lineNumber)
        }
        let whole = try drawn(typed: line.count, cursorIsOn: false)
        // A space is a quarter of the font's size wide: after one, the cursor is that far from the last letter.
        let gap = Int((font.pointSize * 0.45).rounded(.up))
        let block = Int(view.cursorWidth)
        let row = Int(view.rowHeight.rounded(.up))
        var failures = 0
        for typed in 0...line.count {
            let off = try drawn(typed: typed, cursorIsOn: false)
            let on = try drawn(typed: typed, cursorIsOn: true)
            let at = "\(typed) of \(line.count) letters of \"\(line)\" typed, \(what)"
            func check(_ condition: Bool, _ message: String) {
                guard !condition else { return }
                failures += 1
                // One line that breaks at one place fails at many letters: the first few say enough.
                if failures <= 4 { XCTFail("\(message) (\(at))", file: file, line: lineNumber) }
            }
            guard let cursor = on.differingBox(to: off) else {
                check(false, "the cursor is drawn")
                continue
            }
            check(Int(cursor.width) <= block + 1 && Int(cursor.width) >= block - 1, "the cursor is \(block) points wide, not \(cursor.width)")
            check(Int(cursor.height) <= row + 1 && Int(cursor.height) >= row - 2, "and one row high (\(row) points), not \(cursor.height)")
            check(cursor.minX >= 0 && Int(cursor.maxX) <= on.width && Int(cursor.maxY) <= on.height, "inside the view")
            let rows = Int(cursor.minY)...Int(cursor.maxY) - 1
            if let beside = off.inkBox(rows: rows) {
                check(Int(cursor.minX) >= Int(beside.maxX) - 2, "the cursor stands after the last letter of its row")
                check(Int(cursor.minX) - Int(beside.maxX) <= gap, "right after it")
            } else {
                check(Int(cursor.minX) <= 1, "with no letter on its row the cursor is at the row's start")
                check(typed == 0 || off.inkBox(rows: 0...max(0, Int(cursor.minY) - 1)) != nil, "under a row of typed letters")
            }
            check(Int(cursor.maxY) + 3 >= off.height || off.inkBox(rows: (Int(cursor.maxY) + 3)...(off.height - 1)) == nil,
                  "no typed letter is on a row under the cursor")
            // Where the frame differs from the whole line: only after the cursor, on its row or under it.
            let moved = off.count(differingFrom: whole) { x, y in y < Int(cursor.minY) - 1 || (y < Int(cursor.maxY) - 1 && x < Int(cursor.minX) - 2) }
            check(moved == 0, "the typed letters are the whole line's, in their place: \(moved) pixels differ before the cursor")
        }
        if failures > 4 { XCTFail("\(failures) checks failed for \"\(line)\" (\(what))", file: file, line: lineNumber) }
    }

    func testTheHaloStaysInTheRoomAroundTheLogo() throws {
        // The halo is drawn outside the logo, in the padding around it. At the top of a breath, where it is
        // strongest, and a quarter turn later: it shows beside the logo, and it is gone before the screen's edge,
        // the status bar, the title under the logo and, with the phone on its side, the island's side.
        for (moment, name) in [(Moment.brightest, "signin-halo"), (Moment.brightest + 1.5, "signin-halo-later")] {
            let portrait = try bitmaps(SnapshotWriter().write(
                signIn(motion: .at(moment)), name: name, size: Self.portrait.size, safeArea: Self.portrait.safeArea))
            for bitmap in portrait {
                let background = bitmap.at(x: 0, y: bitmap.height - 1)
                func halo(_ x: Int, _ y: Int) -> Int { bitmap.mean(x: x * bitmap.scale, y: y * bitmap.scale, radius: 1).distance(to: background) }
                // The 96-point logo is 16 points from the left edge and 24 under the status bar (59 points).
                let (left, top) = (16, Int(Self.portrait.safeArea.top) + 24)
                let (x, y) = (left + 48, top + 48)
                // Measured, as the distance to the background of 255: 11 to 26 in the light appearance, 33 to 58 in the
                // dark one, 5 points outside the logo; 0 or 1 at the four places where it must be gone.
                for (beside, what) in [(halo(x, top - 5), "over"), (halo(left + 96 + 5, y), "right of"), (halo(x, top + 96 + 5), "under"), (halo(left - 5, y), "left of")] {
                    XCTAssertGreaterThan(beside, 5, "the halo shows \(what) the logo")
                }
                XCTAssertLessThanOrEqual(halo(0, y), 2, "it is gone at the screen's edge")
                XCTAssertLessThanOrEqual(halo(x, top - 23), 2, "under the status bar")
                XCTAssertLessThanOrEqual(halo(x, top + 96 + 16), 2, "and where the title begins")
                XCTAssertLessThanOrEqual(halo(left + 96 + 17, y), 2)
            }
            let landscape = try bitmaps(SnapshotWriter().write(
                signIn(motion: .at(moment)), name: name.replacingOccurrences(of: "signin-", with: "signin-landscape-"),
                size: Self.landscape.size, safeArea: Self.landscape.safeArea))
            for bitmap in landscape {
                let background = bitmap.at(x: 0, y: bitmap.height - 1)
                func halo(_ x: Int, _ y: Int) -> Int { bitmap.mean(x: x * bitmap.scale, y: y * bitmap.scale, radius: 1).distance(to: background) }
                // The 72-point logo is 16 points right of the safe area's edge and 24 from the top.
                let (left, top) = (Int(Self.landscape.safeArea.leading) + 16, 24)
                // Measured: 16 and 25 (light), 33 and 49 (dark) beside the logo; 0 at the edge and at the title.
                XCTAssertGreaterThan(halo(left - 4, top + 36), 5, "the halo shows left of the logo")
                XCTAssertLessThanOrEqual(halo(left - 15, top + 36), 2, "and is gone where the safe area begins")
                XCTAssertLessThanOrEqual(halo(left + 36, top + 72 + 16), 2, "and where the title begins")
            }
        }
    }
}

// MARK: - Bitmap

/// The pixels of a rendered image (test-only).
private struct Bitmap {
    struct Colour {
        let r: Int, g: Int, b: Int

        init(r: Int, g: Int, b: Int) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// `color` as it is in the light or the dark appearance.
        init?(_ color: UIColor?, style: UIUserInterfaceStyle) {
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            guard let color, color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            else { return nil }
            self.init(r: Int((r * 255).rounded()), g: Int((g * 255).rounded()), b: Int((b * 255).rounded()))
        }

        var brightest: Int { max(r, g, b) }
        /// The colour's hue, in degrees (red 0, green 120, blue 240); nil for a grey or one too dark to tell.
        var hue: Double? {
            let (high, low) = (max(r, g, b), min(r, g, b))
            guard high - low >= 12 else { return nil }
            let span = Double(high - low)
            let sixth: Double
            if high == r {
                sixth = (Double(g - b) / span).truncatingRemainder(dividingBy: 6)
            } else if high == g {
                sixth = Double(b - r) / span + 2
            } else {
                sixth = Double(r - g) / span + 4
            }
            return (sixth * 60 + 360).truncatingRemainder(dividingBy: 360)
        }

        /// How far two hues are apart, in degrees, the short way round.
        static func apart(_ a: Double, _ b: Double) -> Double {
            let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(difference, 360 - difference)
        }
        var isWhite: Bool { r >= 250 && g >= 250 && b >= 250 }
        func distance(to other: Colour) -> Int { max(abs(r - other.r), abs(g - other.g), abs(b - other.b)) }
    }

    let width: Int
    let height: Int
    let scale: Int
    private let data: [UInt8]

    var pointSize: CGSize { CGSize(width: width / scale, height: height / scale) }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (w, h) = (cgImage.width, cgImage.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        scale = max(1, Int(image.scale))
        data = bytes
    }

    /// `view` as it draws itself, on white, one pixel a point: its letters and its cursor, cut at its bounds.
    @MainActor
    init?(drawing view: UIView) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        view.contentScaleFactor = 1
        self.init(UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(view.bounds)
            context.cgContext.clip(to: view.bounds)
            view.draw(view.bounds)
        })
    }

    /// How many pixels that satisfy `test` differ from `other`'s.
    func count(differingFrom other: Bitmap, where test: (Int, Int) -> Bool) -> Int {
        guard width == other.width, height == other.height else { return width * height }
        var total = 0
        for y in 0..<height {
            for x in 0..<width where test(x, y) && at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 40 { total += 1 }
        }
        return total
    }

    func at(x: Int, y: Int) -> Colour {
        let i = (y * width + x) * 4
        return Colour(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
    }

    /// The mean colour of the square of pixels up to `radius` away from (x, y).
    func mean(x: Int, y: Int, radius: Int) -> Colour {
        var (r, g, b, n) = (0, 0, 0, 0)
        for row in max(0, y - radius)...min(height - 1, y + radius) {
            for column in max(0, x - radius)...min(width - 1, x + radius) {
                let colour = at(x: column, y: row)
                r += colour.r
                g += colour.g
                b += colour.b
                n += 1
            }
        }
        return Colour(r: r / n, g: g / n, b: b / n)
    }

    func count(where test: (Colour) -> Bool) -> Int {
        var total = 0
        for y in 0..<height {
            for x in 0..<width where test(at(x: x, y: y)) { total += 1 }
        }
        return total
    }

    /// The longest run of white pixels in pixel row `y`, as points from the left edge.
    func longestWhiteRun(pixelRow y: Int) -> Range<Int> {
        var best = 0..<0
        var start: Int?
        for x in 0...width {
            if x < width, at(x: x, y: y).isWhite {
                if start == nil { start = x }
            } else if let from = start {
                if x - from > best.count { best = from..<x }
                start = nil
            }
        }
        return (best.lowerBound / scale)..<(best.upperBound / scale)
    }

    func longestWhiteRun(row: Int) -> Range<Int> { longestWhiteRun(pixelRow: row * scale) }

    /// The first row, in points from the top, with 200 points of white in one run: the top of the Google button,
    /// the only white thing that wide on the screen in either appearance.
    func firstRowWithAWhiteRun() -> Int? {
        for y in stride(from: 0, to: height, by: scale) where longestWhiteRun(pixelRow: y).count >= 200 { return y / scale }
        return nil
    }

    /// Whether every pixel from point row `row` down is the colour of the bottom left corner: only background.
    func isPlain(fromRow row: Int) -> Bool {
        let background = at(x: 0, y: height - 1)
        for y in (row * scale)..<height {
            for x in 0..<width where at(x: x, y: y).distance(to: background) > 2 { return false }
        }
        return true
    }

    /// How many pixel rows from point row `row` down differ from `other`'s.
    func differingRows(to other: Bitmap, fromRow row: Int) -> Int {
        guard width == other.width, height == other.height else { return height }
        var rows = 0
        for y in max(0, row * scale)..<height {
            for x in 0..<width where at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 {
                rows += 1
                break
            }
        }
        return rows
    }

    /// The box, in pixels, around the pixels that differ from `other`; nil when none does.
    func differingBox(to other: Bitmap) -> CGRect? {
        guard width == other.width, height == other.height else { return nil }
        return box { x, y in at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 }
    }

    /// The box, in pixels, around everything that is not black; nil on an all-black image.
    func litBox() -> CGRect? {
        box { x, y in at(x: x, y: y).brightest > 6 }
    }

    /// The box, in pixels, around what is drawn over the background (the colour of the bottom left corner) in the
    /// pixel rows `rows` (all of them when nil); nil when nothing is.
    func inkBox(rows: ClosedRange<Int>? = nil) -> CGRect? {
        let background = at(x: 0, y: height - 1)
        return box(rows: rows) { x, y in at(x: x, y: y).distance(to: background) > 40 }
    }

    private func box(rows: ClosedRange<Int>? = nil, where test: (Int, Int) -> Bool) -> CGRect? {
        var (left, right, top, bottom) = (Int.max, Int.min, Int.max, Int.min)
        let rows = (rows ?? 0...(height - 1)).clamped(to: 0...(height - 1))
        for y in rows {
            for x in 0..<width where test(x, y) {
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard left <= right else { return nil }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// The pixel columns in which this image differs from `other`.
    func differingColumns(to other: Bitmap) -> [Int] {
        guard width == other.width, height == other.height else { return Array(0..<width) }
        return (0..<width).filter { x in
            (0..<height).contains { y in at(x: x, y: y).distance(to: other.at(x: x, y: y)) > 2 }
        }
    }

    /// The side, in points, of the logo's dark square: the longest run of the icon's near-black violet in a row.
    func darkSquareSide() -> Int {
        var best = 0
        for y in stride(from: 0, to: height, by: scale) {
            var run = 0
            for x in 0..<width {
                let colour = at(x: x, y: y)
                // #1C1438 to #0B0716, a little lifted by the inner glow: dark, and more blue than red or green.
                if colour.brightest < 80, colour.b > colour.r + 6, colour.b > colour.g {
                    run += 1
                    best = max(best, run)
                } else {
                    run = 0
                }
            }
        }
        return best / scale
    }

    /// How far this image is from `other`, over the pixels that are not black in one of the two (what is drawn on a
    /// black stage): the mean difference per channel, the share of those pixels with a channel more than 40 away,
    /// and the largest difference of a channel.
    func difference(to other: Bitmap) -> (mean: Double, far: Double, worst: Int) {
        guard width == other.width, height == other.height else { return (255, 1, 255) }
        var sum = 0
        var far = 0
        var worst = 0
        var pixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let (a, b) = (at(x: x, y: y), other.at(x: x, y: y))
                guard a.brightest > 4 || b.brightest > 4 else { continue }
                pixels += 1
                sum += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                let distance = a.distance(to: b)
                worst = max(worst, distance)
                if distance > 40 { far += 1 }
            }
        }
        guard pixels > 0 else { return (255, 1, 255) }
        return (Double(sum) / Double(pixels * 3), Double(far) / Double(pixels), worst)
    }
}

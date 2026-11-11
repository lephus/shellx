import ShellXAppCore
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The sign-in screen with its intro, drawn: on a small phone, on its side and in large type; the logo at rest
/// against the app's own logo; and the intro as it runs (before it starts, while a tagline is typed, after it has
/// settled), where the buttons must be in place from the first frame, the cursor must follow the typed letters
/// and the glow must fade out by itself.
///
/// A test run draws the intro still. The frames of the running intro pass `motion: .animated` and place its start
/// in the future or the past, so what they show does not depend on how long the render takes; the typed line and
/// its cursor are also drawn for a given frame of the typewriter, with no clock at all.
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

    private func signIn(
        motion: SignInIntroMotion? = nil, start: Date = Date(), expired: Bool = false, error: SignInError? = nil
    ) -> SignInView {
        SignInView(
            coordinator: .preview(), expired: expired, startDemo: {}, initialError: error, motion: motion, introStart: start)
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

    func testBeforeTheIntroTheChevronsAreOutsideTheSquareAndThenTheyAreInPlace() throws {
        let side: CGFloat = 240
        let rest = try bitmaps(SnapshotWriter().write(stage(SignInLogoView(size: side, motion: .still)), name: "signin-logo"))
        let before = try bitmaps(SnapshotWriter().write(
            stage(SignInLogoView(size: side, motion: .animated, start: Date().addingTimeInterval(60))), name: "signin-logo-before"))
        let after = try bitmaps(SnapshotWriter().write(
            stage(SignInLogoView(size: side, motion: .animated, start: Date().addingTimeInterval(-30))), name: "signin-logo-after",
            settle: 0.2))
        for index in rest.indices {
            let scale = rest[index].scale
            // The chevrons and the underscore are the only bright things on the stage: mint on the left, near white
            // on the right. Together they cover some 8,000 square points of a 240-point logo.
            let bright = rest[index].count { $0.brightest > 200 }
            XCTAssertGreaterThan(bright, 6000 * scale * scale, "at rest the chevrons are drawn")
            XCTAssertEqual(before[index].count { $0.brightest > 200 }, 0, "before the intro starts the square is empty")
            let settled = after[index].count { $0.brightest > 200 }
            XCTAssertGreaterThan(settled, bright * 9 / 10, "after it they are in place (the underscore may be off)")
            XCTAssertLessThanOrEqual(settled, bright + 50 * scale * scale, "and nothing else is")
            let mint: (Bitmap.Colour) -> Bool = { $0.g > 25 && $0.g > $0.r + 10 }
            XCTAssertGreaterThan(
                after[index].count(where: mint) - rest[index].count(where: mint), 5000 * scale * scale,
                "and a mint glow lies around the square, which the still logo does not have")
        }
    }

    // MARK: - The intro and the buttons

    func testATestRunDrawsTheIntroStill() throws {
        let decided = try SnapshotWriter().write(signIn(), name: "signin-intro")
        let still = try SnapshotWriter().write(signIn(motion: .still), name: "signin-intro")
        XCTAssertEqual(decided.map { $0.pngData() }, still.map { $0.pngData() })
    }

    func testTheButtonsAreInPlaceBeforeTheIntroHasStarted() throws {
        let still = try bitmaps(SnapshotWriter().write(signIn(motion: .still), name: "signin-intro"))
        let before = try bitmaps(SnapshotWriter().write(
            signIn(motion: .animated, start: Date().addingTimeInterval(60)), name: "signin-intro-before"))
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
        // 0.6 s for the logo, then 0.4 s of typing: some 14 letters of the first tagline, and the cursor.
        let typing = try bitmaps(SnapshotWriter().write(
            signIn(motion: .animated, start: Date().addingTimeInterval(-1.0)), name: "signin-intro-typing"))
        let settled = try bitmaps(SnapshotWriter().write(
            signIn(motion: .animated, start: Date().addingTimeInterval(-2.0)), name: "signin-intro-settled", settle: 0.2))
        for (index, style) in [UIUserInterfaceStyle.light, .dark].enumerated() {
            let buttons = try XCTUnwrap(still[index].firstRowWithAWhiteRun())
            XCTAssertEqual(typing[index].firstRowWithAWhiteRun(), buttons)
            XCTAssertEqual(settled[index].firstRowWithAWhiteRun(), buttons)
            XCTAssertEqual(settled[index].differingRows(to: still[index], fromRow: buttons - 8), 0)

            // The still screen has the theme's green in the steps' numbers only; while a line is typed, the cursor
            // is on and adds a block of it (some 4 by 24 points).
            let green = try XCTUnwrap(Bitmap.Colour(UIColor(named: "StatusDone"), style: style))
            let scale = still[index].scale
            let cursor = typing[index].count { $0.distance(to: green) < 24 } - still[index].count { $0.distance(to: green) < 24 }
            XCTAssertGreaterThan(cursor, 40 * scale * scale, "the cursor is drawn after the typed letters")
            XCTAssertLessThan(cursor, 400 * scale * scale, "and it is one small block")
        }
    }

    func testTheCursorTakesNoRoomInTheLine() {
        func width(_ text: AttributedString, _ size: DynamicTypeSize) -> CGFloat {
            let host = UIHostingController(rootView: Text(text).font(.title3).fixedSize().dynamicTypeSize(size))
            return host.sizeThatFits(in: CGSize(width: 4000, height: 400)).width
        }
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility2] {
            let advance = TypedTaglineView.cursorAdvance(size)
            XCTAssertGreaterThan(advance, 2, "\(size)")
            let parts = TypedTaglineView.parts(of: "Control your Mac", typed: 7)
            let letters = width(TypedTaglineView.letters(parts), size)
            let pulledBack = width(TypedTaglineView.cursorLine(parts, isOn: true, advance: advance), size)
            let loose = width(TypedTaglineView.cursorLine(parts, isOn: true, advance: 0), size)
            XCTAssertEqual(loose - letters, advance, accuracy: 0.5, "the measured width is the cursor's own in the text (\(size))")
            XCTAssertEqual(pulledBack, letters, accuracy: 0.5, "with the cursor the line is as wide as without (\(size))")
        }
    }

    func testTheLineIsCutAfterTheTypedLetters() {
        let parts = TypedTaglineView.parts(of: "Đe\u{301}n nơi", typed: 2)
        XCTAssertEqual(parts.typed, "Đe\u{301}")
        XCTAssertEqual(parts.rest, "n nơi")
        XCTAssertEqual(
            String(TypedTaglineView.letters(parts).characters), "Đe\u{301}n nơi▍",
            "the letters are laid out as the whole line with room for the cursor at its end")
        let cursor = TypedTaglineView.cursorLine(parts, isOn: true, advance: 7)
        XCTAssertEqual(String(cursor.characters), "Đe\u{301}▍n nơi▍", "the cursor stands after the typed letters")
        let block = cursor.runs.first { String(cursor[$0.range].characters) == TypedTaglineView.cursor }
        XCTAssertEqual(block?.swiftUI.kern, -7, "and gives its width back")

        let whole = TypedTaglineView.parts(of: "ab", typed: 2)
        let resting = TypedTaglineView.cursorLine(whole, isOn: true, advance: 7)
        XCTAssertEqual(String(resting.characters), "ab▍", "after the last letter the cursor takes the room kept for it")
        XCTAssertTrue(resting.runs.allSatisfy { $0.swiftUI.kern == nil })
        XCTAssertEqual(String(TypedTaglineView.letters(whole).characters), "ab▍")
        XCTAssertEqual(TypedTaglineView.parts(of: "ab", typed: 9).typed, "ab")
        XCTAssertEqual(TypedTaglineView.parts(of: "ab", typed: -1).rest, "ab")
    }

    func testTheCursorShowsAfterTheLastLetterOfAHeldLine() throws {
        // A whole line with the cursor on, in a frame no wider than the line needs: the cursor stands in the room
        // kept for it at the line's end, so it is drawn whole.
        let line = "Control your Mac"
        let tagline = TypedTaglineView(motion: .still, lines: [line])
        let held = TypewriterSchedule.Frame(line: 0, text: line, phase: .holding, nextChange: 1)
        func stage(cursorIsOn: Bool) -> some View {
            tagline.typed(held, cursorIsOn: cursorIsOn, cursorAdvance: TypedTaglineView.cursorAdvance(.large))
                .font(.title3)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
        let on = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: true), name: "signin-tagline-held"))
        let off = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: false), name: "signin-tagline-held-off"))
        for (index, style) in [UIUserInterfaceStyle.light, .dark].enumerated() {
            let green = try XCTUnwrap(Bitmap.Colour(UIColor(named: "StatusDone"), style: style))
            let scale = on[index].scale
            XCTAssertEqual(off[index].count { $0.distance(to: green) < 24 }, 0, "off, the cursor leaves no trace")
            let cursor = on[index].count { $0.distance(to: green) < 24 }
            XCTAssertGreaterThan(cursor, 40 * scale * scale, "on, it is drawn after the last letter")
            XCTAssertLessThan(cursor, 400 * scale * scale)
            // The letters are where they are without the cursor: only the block differs.
            let columns = on[index].differingColumns(to: off[index])
            XCTAssertLessThan(columns.count, 12 * scale, "the two frames differ in a block a few points wide")
        }
    }

    func testTheCursorFollowsTheLettersAlsoInTheMiddleOfAWord() throws {
        // The cursor after one letter, inside a word and before the last letter, in the room the sign-in screen gives
        // the line (361 points, one row) and in a narrow one (220 points, where the line breaks before "your"). On,
        // the cursor adds one block: on the row of the last typed letters, right after the last of them.
        let line = "Control your Mac from your pocket."
        let cases: [(width: CGFloat, typed: String)] = [
            (361, "C"), (361, "Control your Mac from y"), (361, "Control your Mac from your pocke"),
            (220, "Control your M"), (220, "Control your Mac from y"), (220, "Control your Mac from your pocke"),
        ]
        for (width, typed) in cases {
            let letters = try assertTheCursorFollowsTheLetters(of: line, typed: typed.count, width: width)
            if width < 300, typed.count > 30 {
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

    /// Tagline `number` (1 to 3) of the catalog in `language`, whatever language the test runs in.
    private static func tagline(_ number: Int, language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "no \(language).lproj in the app")
        let bundle = try XCTUnwrap(Bundle(path: path))
        let key = "signin.tagline.\(number)"
        let text = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(text, key, "\(key) is not in \(language).lproj")
        return text
    }

    /// Draws `line` with its first `typed` letters and the cursor, on and off, in `width` points, and checks that the
    /// cursor is one narrow block on the row of the last typed letters, right after the last of them, with no typed
    /// letter on a row under it. Returns the box around the typed letters, in points, in the light and the dark
    /// appearance.
    @discardableResult
    private func assertTheCursorFollowsTheLetters(
        of line: String, typed: Int, width: CGFloat, file: StaticString = #filePath, lineNumber: UInt = #line
    ) throws -> [CGRect] {
        let tagline = TypedTaglineView(motion: .still, lines: [line])
        let frame = TypewriterSchedule.Frame(line: 0, text: String(line.prefix(typed)), phase: .typing, nextChange: 1)
        func stage(cursorIsOn: Bool) -> some View {
            tagline.typed(frame, cursorIsOn: cursorIsOn, cursorAdvance: TypedTaglineView.cursorAdvance(.large))
                .font(.title3)
                .lineLimit(2...)
                .frame(width: width, alignment: .leading)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.appBackground)
        }
        let name = "signin-tagline-\(Int(width))-\(line.count)-\(typed)"
        let size = CGSize(width: 393, height: 140)
        let insets = EdgeInsets()
        let on = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: true), name: name, size: size, safeArea: insets))
        let off = try bitmaps(SnapshotWriter().write(stage(cursorIsOn: false), name: name + "-off", size: size, safeArea: insets))
        var boxes: [CGRect] = []
        for index in on.indices {
            let scale = CGFloat(on[index].scale)
            let what = "\(typed) of \(line.count) letters typed, \(Int(width)) points, \(index == 0 ? "light" : "dark")"
            let letters = try XCTUnwrap(off[index].inkBox(), "the typed letters are drawn (\(what))", file: file, line: lineNumber)
            boxes.append(letters.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)))
            let cursor = try XCTUnwrap(
                on[index].differingBox(to: off[index]), "the cursor is drawn (\(what))", file: file, line: lineNumber)
            XCTAssertLessThan(cursor.height, 34 * scale, "the cursor is one row high (\(what))", file: file, line: lineNumber)
            XCTAssertLessThan(cursor.width, 12 * scale, "and a narrow block (\(what))", file: file, line: lineNumber)
            // The typed letters on the cursor's row, and under it.
            let beside = try XCTUnwrap(
                off[index].inkBox(rows: Int(cursor.minY)...Int(cursor.maxY)), "the cursor's row has typed letters (\(what))",
                file: file, line: lineNumber)
            XCTAssertGreaterThanOrEqual(
                cursor.minX, beside.maxX - 2 * scale, "the cursor stands after the last letter (\(what))", file: file, line: lineNumber)
            XCTAssertLessThan(cursor.minX - beside.maxX, 8 * scale, "right after it (\(what))", file: file, line: lineNumber)
            XCTAssertNil(
                off[index].inkBox(rows: (Int(cursor.maxY) + 4 * Int(scale))...(off[index].height - 1)),
                "and no typed letter is on a row under it (\(what))", file: file, line: lineNumber)
        }
        return boxes
    }

    func testTheGlowIsNotCutWhereTheSafeAreaBegins() throws {
        // The glow lies outside the logo, in the padding around it, and reaches a little further. It must fade out
        // on its own: no step where the safe area begins (the island's side with the phone on its side, the status
        // bar upright).
        let landscape = try bitmaps(SnapshotWriter().write(
            signIn(motion: .animated, start: Date().addingTimeInterval(-2.0)), name: "signin-landscape-settled",
            size: Self.landscape.size, safeArea: Self.landscape.safeArea, settle: 0.2))
        for bitmap in landscape {
            let background = bitmap.at(x: 0, y: bitmap.height - 1)
            // The row through the middle of the 72-point logo, which starts 16 points right of the safe area's edge.
            let row = (24 + 36) * bitmap.scale
            func glow(_ x: Int) -> Int { bitmap.at(x: x * bitmap.scale, y: row).distance(to: background) }
            XCTAssertGreaterThan(glow(59 + 14), 12, "the glow is there beside the logo")
            XCTAssertGreaterThanOrEqual(glow(59 + 1), 3, "and still just inside the safe area's edge")
            XCTAssertGreaterThanOrEqual(glow(59 - 2) * 2, glow(59 + 1), "it goes on past that edge: no step down to nothing")
            XCTAssertLessThanOrEqual(glow(59 - 12), 3, "until it has faded out by itself")
        }
        let portrait = try bitmaps(SnapshotWriter().write(
            signIn(motion: .animated, start: Date().addingTimeInterval(-2.0)), name: "signin-intro-settled", settle: 0.2))
        for bitmap in portrait {
            let background = bitmap.at(x: 0, y: bitmap.height - 1)
            // The column through the middle of the 96-point logo, which starts 24 points under the status bar.
            let column = (16 + 48) * bitmap.scale
            func glow(_ y: Int) -> Int { bitmap.at(x: column, y: y * bitmap.scale).distance(to: background) }
            XCTAssertGreaterThan(glow(59 + 22), 12)
            XCTAssertGreaterThanOrEqual(glow(59 + 1), 3)
            XCTAssertGreaterThanOrEqual(glow(59 - 2) * 2, glow(59 + 1))
            XCTAssertLessThanOrEqual(glow(59 - 12), 3)
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

    func at(x: Int, y: Int) -> Colour {
        let i = (y * width + x) * 4
        return Colour(r: Int(data[i]), g: Int(data[i + 1]), b: Int(data[i + 2]))
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

import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkAccount
import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// The sign-in screen with email first, drawn: the field and Send code above "or", Google, Apple and the demo link;
/// how much of the intro each phone keeps; the keyboard up; on its side; large type. `dev.sh screenshots` runs these
/// in English and in Vietnamese, so every fit is checked in both.
@MainActor
final class EmailSignInRenderTests: XCTestCase {
    struct Screen {
        let size: CGSize
        let safeArea: EdgeInsets
    }

    /// iPhone 16, upright.
    static let portrait = Screen(size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    /// iPhone SE (3rd generation), upright: 20 points of status bar, no home indicator.
    static let se = Screen(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
    /// iPhone 16 on its side.
    static let landscape = Screen(size: CGSize(width: 852, height: 393), safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59))

    /// An iPhone SE with a keyboard `height` points high: the system hands the view that much less room below.
    static func seKeyboard(_ height: CGFloat) -> Screen {
        Screen(size: se.size, safeArea: EdgeInsets(top: 20, leading: 0, bottom: height, trailing: 0))
    }

    /// A window of exactly `size` with no insets: the room is the whole window.
    static func room(_ width: CGFloat, _ height: CGFloat) -> Screen {
        Screen(size: CGSize(width: width, height: height), safeArea: EdgeInsets())
    }

    struct Drawn {
        let images: [UIImage]
        let bitmaps: [Bitmap]
        let model: EmailSignInModel
    }

    /// Draws the sign-in screen of a preview coordinator over `relay`, after `drive` has moved its email sign-in.
    private func render(
        _ name: String, on screen: Screen = portrait, relay: FakeRelayAccount = FakeRelayAccount(),
        type: DynamicTypeSize = .large, expired: Bool = false, error: SignInError? = nil, keyboardUp: Bool? = nil,
        _ drive: (EmailSignInModel) async -> Void = { _ in }, file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Drawn {
        let coordinator = AppCoordinator.preview(relay: relay)
        let model = coordinator.emailSignIn
        model.begin()
        await drive(model)
        let view = SignInView(
            coordinator: coordinator, expired: expired, startDemo: {}, initialError: error, motion: .still, keyboardUp: keyboardUp
        )
        .dynamicTypeSize(type)
        let images = try SnapshotWriter().write(view, name: name, size: screen.size, safeArea: screen.safeArea)
        XCTAssertEqual(images.count, 2, file: file, line: line)
        let bitmaps = try images.map { try XCTUnwrap(Bitmap($0), file: file, line: line) }
        return Drawn(images: images, bitmaps: bitmaps, model: model)
    }

    // MARK: - Colours

    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private func colour(_ name: String, _ style: UIUserInterfaceStyle) throws -> Bitmap.Colour {
        try XCTUnwrap(Bitmap.Colour(UIColor(named: name), style: style), name)
    }

    /// The fill of the email field (and of the code field).
    private func surface(_ style: UIUserInterfaceStyle) throws -> Bitmap.Colour { try colour("Surface", style) }

    /// Send code when it can be pressed: the primary fill.
    private func sendOn() throws -> Bitmap.Colour { try XCTUnwrap(Bitmap.Colour(UIColor(PrimaryButtonStyle.fill), style: .light)) }

    /// Send code while it cannot: the primary fill at 40 % over the page.
    private func sendOff(_ style: UIUserInterfaceStyle) throws -> Bitmap.Colour {
        Bitmap.blend(try sendOn(), 0.4, over: try colour("Background", style))
    }

    /// The fill of the "Continue with email" button of the first design (accent at 14 %), which email first removed.
    private func emailButtonTint(_ style: UIUserInterfaceStyle) throws -> Bitmap.Colour {
        Bitmap.blend(try colour("AccentText", style), 0.14, over: try colour("Background", style))
    }

    /// The email field (or the code field): the first band of the surface colour. A run of 60 points is enough, so that
    /// the rows of a typed address keep the field one band.
    private func field(_ bitmap: Bitmap, _ style: UIUserInterfaceStyle, file: StaticString = #filePath, line: UInt = #line) throws
        -> (rows: ClosedRange<Int>, columns: Range<Int>)
    {
        try XCTUnwrap(bitmap.bands(of: try surface(style), atLeast: 60).first, "the field is on the first screen", file: file, line: line)
    }

    private func sendBand(_ bitmap: Bitmap, on: Bool, _ style: UIUserInterfaceStyle) throws -> (rows: ClosedRange<Int>, columns: Range<Int>)? {
        bitmap.band(of: on ? try sendOn() : try sendOff(style), tolerance: 4)
    }

    // MARK: - The first screen

    func testTheFirstScreenIsTheEmailStepAboveGoogleAppleAndTheDemoLink() async throws {
        let drawn = try await render("signin-email-first")
        XCTAssertEqual(drawn.model.step, .email, "the screen starts at the email step")
        for (bitmap, style) in zip(drawn.bitmaps, Self.styles) {
            let field = try field(bitmap, style)
            XCTAssertGreaterThan(field.columns.count, 393 - 32 - 4, "the field is as wide as the column")
            XCTAssertGreaterThanOrEqual(field.rows.count, 48, "and 50 points high")
            let send = try XCTUnwrap(sendBand(bitmap, on: false, style), "Send code is there, and off on an empty field")
            XCTAssertNil(try self.sendBand(bitmap, on: true, style), "never on with nothing typed")
            XCTAssertEqual(send.rows.lowerBound, field.rows.upperBound + 1 + 12, accuracy: 2, "right under the field")
            let google = try XCTUnwrap(bitmap.googleButtonTop())
            XCTAssertGreaterThan(google, send.rows.upperBound + 12 + 12 + 12, "then the line with \"or\", then Google")
            XCTAssertLessThanOrEqual(google + 44 + 12 + 44 + 12 + 44 + 24, 852 - 34, "Apple and the demo link fit above the home indicator")
            XCTAssertNil(bitmap.band(of: try emailButtonTint(style)), "no \"Continue with email\" button")
        }
        // In the light appearance the logo's dark square stands out: the iPhone 16 keeps the large logo and the steps.
        XCTAssertGreaterThan(drawn.bitmaps[0].darkSquareSide(), 90)
    }

    func testAnAddressTurnsSendCodeOnAndALetterOutsideASCIISaysWhyItStaysOff() async throws {
        let typed = try await render("signin-email-typed") { $0.email = "phu@example.com" }
        let telex = try await render("signin-email-not-ascii") { $0.email = "phu@ẽample.com" }
        XCTAssertTrue(typed.model.canSend)
        XCTAssertFalse(telex.model.canSend)
        for index in Self.styles.indices {
            let style = Self.styles[index]
            let on = try XCTUnwrap(try sendBand(typed.bitmaps[index], on: true, style), "an address turns Send code on")
            XCTAssertNil(try sendBand(telex.bitmaps[index], on: true, style), "\"ẽ\" keeps it off")
            let off = try XCTUnwrap(try sendBand(telex.bitmaps[index], on: false, style))
            let field = try field(telex.bitmaps[index], style)
            XCTAssertGreaterThan(off.rows.lowerBound, on.rows.lowerBound + 16, "a line of words under the field pushes Send code down")
            let red = try colour("StatusError", style)
            let words = telex.bitmaps[index].count { $0.distance(to: red) < 40 }
            let scale = telex.bitmaps[index].scale
            XCTAssertGreaterThan(words, 150 * scale * scale, "it says, in the error colour, that this is not an address")
            XCTAssertGreaterThan(off.rows.lowerBound, field.rows.upperBound + 20)
        }
    }

    func testNoticesStandOverTheFieldAndAnEmailFailureUnderIt() async throws {
        let relay = FakeRelayAccount()
        await relay.setError(RelayAPIError.http(status: 400, code: "disposable_email"), for: .requestEmailCode)
        let drawn = try await render("signin-email-messages", relay: relay, expired: true, error: .providerFailed) { model in
            model.email = "phu@example.com"
            await model.sendCode()
        }
        XCTAssertEqual(drawn.model.error, .disposableEmail)
        for (bitmap, style) in zip(drawn.bitmaps, Self.styles) {
            let field = try field(bitmap, style)
            let send = try XCTUnwrap(try sendBand(bitmap, on: true, style))
            let error = try colour("StatusError", style)
            let needsYou = try colour("StatusNeedsYou", style)
            let above = field.rows.lowerBound - 1
            XCTAssertNotNil(rows(in: bitmap, to: above) { $0.distance(to: needsYou) < 30 }, "\"session expired\" stands over the field")
            XCTAssertNotNil(rows(in: bitmap, to: above) { $0.distance(to: error) < 30 }, "Google's failure stands over the field too")
            let below = rows(in: bitmap, from: field.rows.upperBound + 1, to: send.rows.lowerBound - 1) { $0.distance(to: error) < 30 }
            XCTAssertNotNil(below, "the email failure stands between the field and Send code")
        }
    }

    /// The first and last point rows, between `from` and `to`, with a pixel that passes `test`; nil when none has.
    private func rows(in bitmap: Bitmap, from: Int = 0, to: Int? = nil, where test: (Bitmap.Colour) -> Bool) -> ClosedRange<Int>? {
        let last = min(to ?? Int.max, bitmap.height / bitmap.scale - 1)
        guard from <= last else { return nil }
        var found: [Int] = []
        for row in from...last {
            let y = row * bitmap.scale + bitmap.scale / 2
            if (0..<bitmap.width).contains(where: { test(bitmap.at(x: $0, y: y)) }) { found.append(row) }
        }
        guard let first = found.first, let end = found.last else { return nil }
        return first...end
    }

    // MARK: - Room

    func testOnASmallPhoneTheWholeFirstScreenFitsWithoutScrolling() async throws {
        let drawn = try await render("signin-email-first-se", on: Self.se)
        for (bitmap, style) in zip(drawn.bitmaps, Self.styles) {
            _ = try field(bitmap, style)
            let google = try XCTUnwrap(bitmap.googleButtonTop())
            XCTAssertLessThanOrEqual(google + 44 + 12 + 44 + 12 + 44 + 24, 667, "Apple, the demo link and the margin fit")
            XCTAssertTrue(bitmap.isPlain(fromRow: 667 - 12))
        }
        XCTAssertGreaterThan(drawn.bitmaps[0].darkSquareSide(), 90, "the SE keeps the large logo; the steps made room")
        XCTAssertLessThan(drawn.bitmaps[0].darkSquareSide(), 100)
    }

    /// Each threshold of `SignInLayout` on its worst window (the narrowest iPhone, 375 points): at the height where
    /// a part of the intro comes back, everything still fits. Checked in English and Vietnamese by `dev.sh screenshots`.
    func testEachThresholdLeavesRoomForWhatItShows() async throws {
        let windows: [(String, CGFloat)] = [
            ("subtitle", SignInLayout.subtitleHeight), ("guide", SignInLayout.guideHeight),
            ("large-logo", SignInLayout.largeLogoHeight), ("small-logo", SignInLayout.largeLogoHeight - 1),
        ]
        for (name, height) in windows {
            let drawn = try await render("signin-email-fit-\(name)", on: Self.room(375, height))
            for bitmap in drawn.bitmaps {
                let google = try XCTUnwrap(bitmap.googleButtonTop(), name)
                XCTAssertLessThanOrEqual(google + 44 + 12 + 44 + 12 + 44 + 24, Int(height), "\(name): \(height) points hold it all")
            }
        }
        // On its side: the steps over the field from `sidewaysGuideHeight`.
        let height = SignInLayout.sidewaysGuideHeight
        let side = try await render("signin-email-fit-side-guide", on: Self.room(734, height))
        for bitmap in side.bitmaps {
            let google = try XCTUnwrap(bitmap.googleButtonTop())
            XCTAssertGreaterThan(google, 24 + 3 * 28 + 2 * 12 + 16 + 50 + 12 + 50, "the steps stand over the field")
            XCTAssertLessThanOrEqual(google + 44 + 12 + 44 + 12 + 44 + 24, Int(height))
        }
    }

    func testOnItsSideTheFieldAndTheButtonsAreBesideTheIntro() async throws {
        let drawn = try await render("signin-email-first-landscape", on: Self.landscape)
        for (bitmap, style) in zip(drawn.bitmaps, Self.styles) {
            let field = try field(bitmap, style)
            XCTAssertGreaterThan(field.columns.lowerBound, 852 / 2, "in the right column")
            let google = try XCTUnwrap(bitmap.googleButtonTop())
            XCTAssertLessThanOrEqual(google + 44 + 12 + 44 + 12 + 44 + 24, 393 - 21)
            XCTAssertTrue(bitmap.isPlain(fromRow: 393 - 21))
        }
        let logo = drawn.bitmaps[0].darkSquareSide()
        XCTAssertGreaterThan(logo, 66, "the logo is 72 points on its side")
        XCTAssertLessThan(logo, 76)
    }

    // MARK: - The keyboard

    func testWithTheKeyboardUpTheIntroFoldsAndTheFieldAndSendCodeStayAboveIt() async throws {
        let keyboard = try await render("signin-email-se-keyboard", on: Self.seKeyboard(260), keyboardUp: true)
        let tall = try await render("signin-email-se-tall-keyboard", on: Self.seKeyboard(300), keyboardUp: true)
        let side = try await render(
            "signin-email-landscape-keyboard",
            on: Screen(size: Self.landscape.size, safeArea: EdgeInsets(top: 0, leading: 59, bottom: 200, trailing: 59)),
            keyboardUp: true)
        for (index, style) in Self.styles.enumerated() {
            let send = try XCTUnwrap(try sendBand(keyboard.bitmaps[index], on: false, style))
            XCTAssertLessThanOrEqual(send.rows.upperBound, 667 - 260, "Send code is above a 260-point keyboard")
            // 375 x 347 of room is wider than high: still one column.
            let tallField = try field(tall.bitmaps[index], style)
            XCTAssertGreaterThan(tallField.columns.count, 300, "one column under a tall keyboard")
            let tallSend = try XCTUnwrap(try sendBand(tall.bitmaps[index], on: false, style))
            XCTAssertLessThanOrEqual(tallSend.rows.upperBound, 667 - 300)
            let sideSend = try XCTUnwrap(try sendBand(side.bitmaps[index], on: false, style))
            XCTAssertLessThanOrEqual(sideSend.rows.upperBound, 393 - 200, "on its side too")
            XCTAssertGreaterThan(sideSend.columns.lowerBound, 852 / 2)
        }
        let logo = keyboard.bitmaps[0].darkSquareSide()
        XCTAssertGreaterThan(logo, 42, "folded, the logo is 48 points")
        XCTAssertLessThan(logo, 52)
    }

    func testAnAddressKeepsTheIntroFoldedWhenTheKeyboardGoesDown() async throws {
        let empty = try await render("signin-email-first-se", on: Self.se)
        let typed = try await render("signin-email-typed-se", on: Self.se) { $0.email = "phu@example.com" }
        XCTAssertGreaterThan(empty.bitmaps[0].darkSquareSide(), 90, "an empty field: the whole intro")
        XCTAssertLessThan(typed.bitmaps[0].darkSquareSide(), 52, "an address typed: the intro stays folded")
    }

    // MARK: - Large type

    func testLargeTypeRenders() async throws {
        let plain = try await render("signin-email-first")
        let large = try await render("signin-email-first-large-type", type: .xxxLarge)
        XCTAssertNotEqual(plain.images.first?.pngData(), large.images.first?.pngData())
        for (bitmap, style) in zip(large.bitmaps, Self.styles) {
            _ = try field(bitmap, style)
        }
        _ = try await render("signin-email-first-accessibility-type", on: Self.se, type: .accessibility2)
        _ = try await render("signin-email-se-keyboard-large-type", on: Self.seKeyboard(260), type: .xxxLarge, keyboardUp: true)
    }
}

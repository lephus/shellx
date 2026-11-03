import AppKit
import Bonsplit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class ShellXAutomationsSidebarButtonTests: XCTestCase {
    func testRingAnimatesByDefault() {
        let (button, window) = Self.makeButton(environment: MotionEnvironment(reducesMotion: false))
        defer { window.close() }

        XCTAssertTrue(button.isRingAnimating)
        XCTAssertTrue(button.isTwinkling)
        let turn = button.gradientLayer.animation(forKey: ShellXAutomationsSidebarButton.ringAnimationKey) as? CABasicAnimation
        XCTAssertEqual(turn?.keyPath, "transform.rotation.z")
        XCTAssertEqual(turn?.duration, 4)
        XCTAssertEqual(turn?.repeatCount, .infinity)
        XCTAssertEqual(button.gradientLayer.type, .conic)
        // Only layers animate: the ring's colors are the five constraint colors.
        let colors = (button.gradientLayer.colors as? [CGColor]) ?? []
        XCTAssertEqual(colors.count, 6)
    }

    func testRingStaysStillOutsideAWindow() {
        let button = ShellXAutomationsSidebarButton(environment: MotionEnvironment(reducesMotion: false))
        button.frame = NSRect(x: 0, y: 0, width: 240, height: 28)
        button.layoutSubtreeIfNeeded()

        XCTAssertFalse(button.isRingAnimating)
    }

    func testReduceMotionStopsRing() {
        let environment = MotionEnvironment(reducesMotion: false)
        let (button, window) = Self.makeButton(environment: environment)
        defer { window.close() }
        XCTAssertTrue(button.isRingAnimating)

        button.reduceMotion = true
        XCTAssertFalse(button.isRingAnimating)
        XCTAssertFalse(button.isTwinkling)

        button.reduceMotion = false
        XCTAssertTrue(button.isRingAnimating)

        environment.reducesMotion = true
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )
        XCTAssertTrue(button.reduceMotion)
        XCTAssertFalse(button.isRingAnimating)
    }

    /// The ring and the ✦ rest while ShellX is in the background and resume when it is active again.
    func testRingStopsWhileTheAppIsInactive() {
        let environment = MotionEnvironment(reducesMotion: false)
        let (button, window) = Self.makeButton(environment: environment)
        defer { window.close() }
        XCTAssertTrue(button.isRingAnimating)

        environment.isAppActive = false
        environment.notificationCenter.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertFalse(button.isRingAnimating)
        XCTAssertFalse(button.isTwinkling)

        environment.isAppActive = true
        environment.notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(button.isRingAnimating)
        XCTAssertTrue(button.isTwinkling)
    }

    func testRingStaysStillWhenAddedWhileTheAppIsInactive() {
        let environment = MotionEnvironment(reducesMotion: false)
        environment.isAppActive = false
        let (button, window) = Self.makeButton(environment: environment)
        defer { window.close() }

        XCTAssertFalse(button.isRingAnimating)
        XCTAssertFalse(button.isTwinkling)
    }

    func testCountPillHiddenAtZero() {
        let (button, window) = Self.makeButton(environment: MotionEnvironment(reducesMotion: true))
        defer { window.close() }
        XCTAssertFalse(button.isCountVisible)

        button.count = 3
        XCTAssertTrue(button.isCountVisible)
        XCTAssertTrue(button.accessibilityLabel()?.contains("3") == true)

        button.count = 0
        XCTAssertFalse(button.isCountVisible)
    }

    func testClickCallsOnClick() {
        let (button, window) = Self.makeButton(environment: MotionEnvironment(reducesMotion: true))
        defer { window.close() }
        var clicks = 0
        button.onClick = { clicks += 1 }

        button.performClick(nil)
        XCTAssertEqual(clicks, 1)
        XCTAssertTrue(button.accessibilityPerformPress())
        XCTAssertEqual(clicks, 2)
        // Labels inside never take the click from the button.
        let center = NSPoint(x: button.frame.midX, y: button.frame.midY)
        XCTAssertTrue(button.superview?.hitTest(center) === button)
    }

    func testBrandHeaderHeightIs98() {
        XCTAssertEqual(ShellXSidebarHeaderMetrics.automationsRowHeight, 36)
        XCTAssertEqual(ShellXSidebarHeaderMetrics.brandHeight, 98)
        XCTAssertEqual(ShellXSidebarHeaderRow.brand.rowHeight, 98)
    }

    func testBrandHeaderPlacesButtonBetweenBrandAndMachines() {
        let cell = SidebarBrandHeaderCellView(frame: NSRect(x: 0, y: 0, width: 260, height: 98))
        cell.layoutSubtreeIfNeeded()

        let frame = cell.automationsButton.frame
        XCTAssertEqual(frame.height, 28)
        XCTAssertEqual(frame.minX, SidebarWorkspaceListMetrics.rowOuterHorizontalPadding)
        XCTAssertEqual(frame.width, 260 - 2 * SidebarWorkspaceListMetrics.rowOuterHorizontalPadding)
        XCTAssertGreaterThanOrEqual(frame.minY, ShellXSidebarHeaderMetrics.brandLineHeight)
        XCTAssertLessThanOrEqual(frame.maxY, ShellXSidebarHeaderMetrics.brandLineHeight + ShellXSidebarHeaderMetrics.automationsRowHeight)
    }

    // MARK: - Helpers

    /// An environment whose Reduce Motion and app activity a test can flip; the view can be seen while in a window.
    /// App activity notifications go through its own center so the host app never sees them.
    @MainActor
    private final class MotionEnvironment: TitleEffectEnvironment {
        var reducesMotion: Bool
        var isAppActive = true
        let notificationCenter = NotificationCenter()

        init(reducesMotion: Bool) {
            self.reducesMotion = reducesMotion
        }

        func isVisible(_ view: NSView) -> Bool {
            !view.isHiddenOrHasHiddenAncestor && view.window != nil
        }
    }

    private static func makeButton(environment: MotionEnvironment) -> (ShellXAutomationsSidebarButton, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
        window.contentView = host
        let button = ShellXAutomationsSidebarButton(
            environment: environment,
            notificationCenter: environment.notificationCenter,
            isApplicationActive: { [environment] in environment.isAppActive }
        )
        button.frame = NSRect(x: 6, y: 6, width: 248, height: 28)
        host.addSubview(button)
        host.layoutSubtreeIfNeeded()
        return (button, window)
    }
}

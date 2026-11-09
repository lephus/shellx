import CoreGraphics
import XCTest
@testable import ShellXAppCore

final class TerminalGeometryTests: XCTestCase {
    func testPhoneGridFitsTheViewport() {
        let grid = TerminalGeometry.phoneGrid(viewport: CGSize(width: 375, height: 646), cell: CGSize(width: 7.2, height: 15))
        XCTAssertEqual(grid.cols, 50); XCTAssertEqual(grid.rows, 42)
        let tiny = TerminalGeometry.phoneGrid(viewport: .zero, cell: CGSize(width: 7.2, height: 15))
        XCTAssertEqual(tiny.cols, 1); XCTAssertEqual(tiny.rows, 1)
    }

    func testFitScaleShrinksAWiderGridAndNeverEnlarges() {
        XCTAssertEqual(TerminalGeometry.fitScale(cols: 120, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 367 / 864, accuracy: 0.0001)
        XCTAssertEqual(TerminalGeometry.fitScale(cols: 40, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 1)
        XCTAssertEqual(TerminalGeometry.fitScale(cols: 320, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 367 / 2304, accuracy: 0.0001,
                       "a Mac-sized grid beyond the phone's 300-column limit (contracts §17)")
    }

    func testScrollLinesKeepTheRest() {
        let first = TerminalGeometry.scrollLines(translation: 47, carry: 0, lineHeight: 15, scale: 1)
        XCTAssertEqual(first.lines, 3); XCTAssertEqual(first.carry, 2, accuracy: 0.001)
        let up = TerminalGeometry.scrollLines(translation: -20, carry: first.carry, lineHeight: 15, scale: 1)
        XCTAssertEqual(up.lines, -1); XCTAssertEqual(up.carry, -3, accuracy: 0.001)
        XCTAssertEqual(TerminalGeometry.scrollLines(translation: 30, carry: 0, lineHeight: 15, scale: 0.5).lines, 4)
    }
}

/// Review Focus 5.
final class TerminalZoomTests: XCTestCase {
    func testANewGridWidthGoesBackToFit() {
        var zoom = TerminalZoom()
        zoom.gridChanged(cols: 100); zoom.pinch(to: 1, fit: 0.5)
        zoom.gridChanged(cols: 100); XCTAssertEqual(zoom.scale(fit: 0.5), 1, "frames of the same width keep the pinch")
        zoom.gridChanged(cols: 50); XCTAssertNil(zoom.zoom); XCTAssertEqual(zoom.scale(fit: 1), 1)
    }

    func testPinchStaysBetweenFitAndTwo() {
        var zoom = TerminalZoom()
        zoom.pinch(to: 0.1, fit: 0.5); XCTAssertEqual(zoom.scale(fit: 0.5), 0.5)
        zoom.pinch(to: 9, fit: 0.5); XCTAssertEqual(zoom.scale(fit: 0.5), 2)
    }

    func testAZoomBelowANewFitFollowsTheFit() {
        var zoom = TerminalZoom()
        zoom.pinch(to: 0.6, fit: 0.5)
        XCTAssertEqual(zoom.scale(fit: 0.8), 0.8, "a wider pane after rotation: never smaller than fit")
    }
}

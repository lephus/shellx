import SwiftUI
import UIKit
import XCTest
@testable import ShellX

/// A SwiftUI view live in a key window of the test host, for tests that need focus, layout and `.task`s to run: the
/// window goes away when the test ends.
@MainActor
final class WindowHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>

    init(_ view: some View, size: CGSize = CGSize(width: 393, height: 760), in test: XCTestCase) {
        let bounds = CGRect(origin: .zero, size: size)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: bounds)
        window.frame = bounds
        let controller = UIHostingController(rootView: AnyView(view))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        self.controller = controller
        test.addTeardownBlock { @MainActor in
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// Every terminal surface in the window.
    var surfaces: [TerminalSurfaceView] { Self.surfaces(in: window) }

    /// The first surface, once there is one.
    func surface(file: StaticString = #filePath, line: UInt = #line) async throws -> TerminalSurfaceView {
        _ = await WorkspaceRig.eventually { !surfaces.isEmpty }
        return try XCTUnwrap(surfaces.first, "no terminal surface in the window", file: file, line: line)
    }

    private static func surfaces(in view: UIView) -> [TerminalSurfaceView] {
        var found: [TerminalSurfaceView] = []
        if let surface = view as? TerminalSurfaceView { found.append(surface) }
        for subview in view.subviews { found += surfaces(in: subview) }
        return found
    }
}

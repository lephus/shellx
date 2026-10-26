import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

// The title bar's right sidebar button (ShellX): lit while the host window's
// right sidebar is open, and its click toggles that window's sidebar.

@MainActor
@Suite struct ShellXRightSidebarToggleTests {
    private func makeState() throws -> (FileExplorerState, UserDefaults, String) {
        let suiteName = "ShellXRightSidebarToggleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (FileExplorerState(defaults: defaults), defaults, suiteName)
    }

    @Test func buttonFollowsTheBoundSidebarVisibility() throws {
        let (state, defaults, suiteName) = try makeState()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = ShellXRightSidebarToggleModel()

        model.bind(to: state)
        #expect(!model.isOn)

        state.toggle()
        #expect(model.isOn)

        state.toggle()
        #expect(!model.isOn)
    }

    @Test func rebindingFollowsOnlyTheNewWindowsSidebar() throws {
        let (first, firstDefaults, firstSuite) = try makeState()
        let (second, secondDefaults, secondSuite) = try makeState()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuite)
            secondDefaults.removePersistentDomain(forName: secondSuite)
        }
        let model = ShellXRightSidebarToggleModel()
        first.toggle()
        model.bind(to: first)
        #expect(model.isOn)

        model.bind(to: second)
        #expect(!model.isOn)
        first.toggle()
        first.toggle()
        #expect(!model.isOn)

        model.bind(to: nil)
        #expect(!model.isOn)
    }

    @Test func accessoryBindsItsWindowAndTogglesThatWindow() throws {
        let (state, defaults, suiteName) = try makeState()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        var toggledWindows: [NSWindow?] = []
        let accessory = ShellXTitlebarAccessoryViewController(
            resolveRightSidebarState: { $0 === window ? state : nil },
            toggleRightSidebar: { toggledWindows.append($0); state.toggle() }
        )

        window.addTitlebarAccessoryViewController(accessory)
        #expect(!accessory.rootView.rightSidebarToggle.isOn)

        accessory.rootView.onToggleRightSidebar()
        #expect(toggledWindows.count == 1)
        #expect(toggledWindows.first.flatMap { $0 } === window)
        #expect(accessory.rootView.rightSidebarToggle.isOn)

        state.toggle()
        #expect(!accessory.rootView.rightSidebarToggle.isOn)
    }
}

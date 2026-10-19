import Testing
@testable import ShellXBrand

@Suite struct ShellXTitlebarModelTests {
    @Test func badgeText() {
        #expect(ShellXTitlebarModel(unreadCount: 0).badgeText == nil)
        #expect(ShellXTitlebarModel(unreadCount: 1).badgeText == "1")
        #expect(ShellXTitlebarModel(unreadCount: 3).badgeText == "3")
        #expect(ShellXTitlebarModel(unreadCount: 9).badgeText == "9")
        #expect(ShellXTitlebarModel(unreadCount: 10).badgeText == "9+")
        #expect(ShellXTitlebarModel(unreadCount: 12).badgeText == "9+")
        #expect(ShellXTitlebarModel(unreadCount: 1000).badgeText == "9+")
    }

    @Test func negativeCountClampsToNoBadge() {
        #expect(ShellXTitlebarModel(unreadCount: -4).badgeText == nil)
        #expect(ShellXTitlebarModel(unreadCount: -4).unreadCount == 0)
    }

    @Test func defaultPlaceholder() {
        #expect(ShellXTitlebarModel(unreadCount: 0).searchPlaceholder == "Search sessions, machines, commands…")
    }

    @Test func equatable() {
        #expect(ShellXTitlebarModel(unreadCount: 2) == ShellXTitlebarModel(unreadCount: 2))
        #expect(ShellXTitlebarModel(unreadCount: 2) != ShellXTitlebarModel(unreadCount: 3))
    }
}

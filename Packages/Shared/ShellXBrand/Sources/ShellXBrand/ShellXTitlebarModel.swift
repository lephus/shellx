/// Pure state of the ShellX title bar (spec §7.1): the unread count behind
/// the bell badge and the search field's placeholder.
public struct ShellXTitlebarModel: Equatable, Sendable {
    /// English default; the app localizes it at the view
    /// (`titlebar.search.placeholder`).
    public static let defaultSearchPlaceholder = "Search sessions, machines, commands…"

    public let unreadCount: Int
    public let searchPlaceholder: String

    public init(unreadCount: Int, searchPlaceholder: String = ShellXTitlebarModel.defaultSearchPlaceholder) {
        self.unreadCount = max(0, unreadCount)
        self.searchPlaceholder = searchPlaceholder
    }

    /// nil for 0, "1"..."9", then "9+".
    public var badgeText: String? {
        switch unreadCount {
        case 0: return nil
        case 1...9: return String(unreadCount)
        default: return "9+"
        }
    }
}

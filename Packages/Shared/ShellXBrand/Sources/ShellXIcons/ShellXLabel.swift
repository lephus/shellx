import SwiftUI

/// SwiftUI's SF Symbol `Label` initializer, with the icon drawn through ``ShellXIcon``.
///
/// Takes the same title types as `Label`: a literal is a
/// `LocalizedStringKey` (looked up in the main bundle, like `Label`), a
/// `String` is shown verbatim, and a `LocalizedStringResource` is resolved
/// with its own bundle.
public struct ShellXLabel: View {
    private let title: Text
    private let icon: String

    public init(_ titleKey: LocalizedStringKey, icon: String) {
        self.title = Text(titleKey)
        self.icon = icon
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, icon: String) {
        self.title = Text(title)
        self.icon = icon
    }

    @_disfavoredOverload
    public init(_ title: LocalizedStringResource, icon: String) {
        self.title = Text(title)
        self.icon = icon
    }

    public var body: some View {
        Label {
            title
        } icon: {
            ShellXIcon.image(icon)
        }
    }
}

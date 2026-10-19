import Foundation
import ShellXBrand

/// Help menu links. ShellX has no docs site of its own yet, so the menu offers
/// the ShellX website and the source code instead of cmux's docs pages.
enum CmuxHelpResource {
    case website
    case sourceCode

    var title: String {
        switch self {
        case .website:
            return String(localized: "menu.help.shellxWebsite", defaultValue: "ShellX website")
        case .sourceCode:
            return String(localized: "menu.help.sourceCode", defaultValue: "Source code")
        }
    }

    var url: URL {
        switch self {
        case .website:
            return ShellXBrand.websiteURL
        case .sourceCode:
            return ShellXBrand.sourceCodeURL
        }
    }
}

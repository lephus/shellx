import SwiftUI

extension Color {
    /// Behind every screen: iOS's grouped grey in light, shellx.pro's violet (#0b0716) in dark.
    static let appBackground = Color("Background")
    /// Cards, fields, chips and list rows over `appBackground`: white in light, a lifted violet in dark.
    static let appSurface = Color("Surface")
}

extension View {
    /// A `List` over the app's background instead of the system's; its rows set
    /// `listRowBackground(Color.appSurface)` (or clear, for cards that draw their own).
    func themedList() -> some View {
        scrollContentBackground(.hidden).background(Color.appBackground)
    }
}

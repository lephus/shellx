import SwiftUI
import Testing
@testable import ShellXRemoteUI

@Test func lightThemeIsGooglesLightTheme() {
    #expect(GoogleSignInButtonSpec.fill == 0xFFFFFF)
    #expect(GoogleSignInButtonSpec.stroke == 0x747775)
    #expect(GoogleSignInButtonSpec.text == 0x1F1F1F)
}

@Test func metricsAreGooglesAndroidAndWebButton() {
    typealias S = GoogleSignInButtonSpec
    #expect([S.height, S.cornerRadius, S.strokeWidth, S.logoSize, S.leadingPadding, S.logoGap,
             S.trailingPadding, S.fontSize, S.lineHeight] == [40, 4, 1, 20, 12, 10, 12, 14, 20])
}

@Test func googleSansOnlyWhenItsFaceIsRegistered() {
    #expect(GoogleSignInButtonSpec.font(isAvailable: { $0 == "GoogleSans-Medium" }) == .custom("GoogleSans-Medium", size: 14))
    #expect(GoogleSignInButtonSpec.font(isAvailable: { _ in false }) == .system(size: 14, weight: .medium))
}

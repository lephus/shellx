import Testing
@testable import CmuxSettings

/// Where the sidebar color comes from is stored under `sidebarTintSource`.
/// Untouched installs read `automatic`, which keeps a tint changed before the
/// choice existed.
@Suite struct SidebarTintSourceSettingTests {
    private let key = SettingCatalog().sidebarAppearance.tintSource

    @Test func untouchedInstallsReadAutomatic() {
        #expect(key.id == "sidebarAppearance.tintSource")
        #expect(key.userDefaultsKey == "sidebarTintSource")
        #expect(key.defaultValue == .automatic)
    }

    @Test func storedChoiceRoundTrips() {
        for source in SidebarTintSourceOption.allCases {
            #expect(SidebarTintSourceOption.decodeFromUserDefaults(source.encodeForUserDefaults()) == source)
        }
        #expect(SidebarTintSourceOption.decodeFromUserDefaults("unknown") == nil)
    }
}

import Foundation
import ShellXBrand
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("ShellX About panel")
struct ShellXAboutTests {
    @Test func aboutCreditsUpstreamAndAssets() {
        let names = AboutLicenseContent.attributions.map(\.name)
        #expect(names.contains("cmux (Manaflow, Inc.)"))
        #expect(names.contains("Ghostty"))
        #expect(names.contains("coolicons by Kryston Schwarze"))
        #expect(names.contains("Space Grotesk"))
        #expect(AboutLicenseContent.sourceCodeURL == ShellXBrand.sourceCodeURL)
    }

    @Test func attributionsCarryTheirLicenses() {
        let licenses = Dictionary(
            uniqueKeysWithValues: AboutLicenseContent.attributions.map { ($0.name, $0.license) }
        )
        #expect(licenses["cmux (Manaflow, Inc.)"] == "GPL-3.0-or-later")
        #expect(licenses["Ghostty"] == "MIT")
        #expect(licenses["coolicons by Kryston Schwarze"] == "CC BY 4.0")
        #expect(licenses["Space Grotesk"] == "OFL-1.1")
    }

    @Test func licenseLineNamesTheShellXSource() {
        #expect(AboutLicenseContent.sourceCodeDisplay == "github.com/lephus/shellx")
        #expect(AboutLicenseContent.licenseLine.contains("GPL-3.0-or-later"))
        #expect(AboutLicenseContent.licenseLine.contains("github.com/lephus/shellx"))
    }

    @Test func defaultRepositoryIsTheShellXSource() {
        #expect(AboutLicenseContent(bundle: .main).repositoryURL == ShellXBrand.sourceCodeURL)
    }
}

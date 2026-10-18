import CmuxWindowing
import Foundation
import Testing

/// A Flutter ShellX at /Applications/ShellX.app shares our bundle id. The
/// native app must ask before quitting it, never exit silently and never kill
/// it without the user's click (plan Review Focus #5, ruling R6).
@Suite("Older (non-native) ShellX sharing the bundle id")
struct OlderShellXConflictTests {
    private let flutter = URL(fileURLWithPath: "/Applications/ShellX.app", isDirectory: true)
    private let native = URL(fileURLWithPath: "/Applications/ShellX Next.app", isDirectory: true)
    private let current = URL(fileURLWithPath: "/Users/dev/Build/ShellX DEV w1.app", isDirectory: true)

    private func files(_ paths: Set<String>) -> (String) -> Bool { { paths.contains($0) } }

    @Test("a bundle with the Flutter engine is an older ShellX")
    func flutterBundleIsOlder() {
        let kind = SingleInstanceConflictPolicy.classifyExistingBundle(
            at: flutter,
            fileExists: files(["/Applications/ShellX.app/Contents/Frameworks/FlutterMacOS.framework"])
        )
        #expect(kind == .olderShellX)
    }

    @Test("a bundle without the bundled shellx CLI is an older ShellX")
    func bundleWithoutCLIIsOlder() {
        #expect(SingleInstanceConflictPolicy.classifyExistingBundle(at: flutter, fileExists: files([])) == .olderShellX)
    }

    @Test("a bundle that ships Contents/Resources/bin/shellx is a native ShellX")
    func nativeBundle() {
        let kind = SingleInstanceConflictPolicy.classifyExistingBundle(
            at: native,
            fileExists: files(["/Applications/ShellX Next.app/Contents/Resources/bin/shellx"])
        )
        #expect(kind == .nativeShellX)
    }

    @Test("the Flutter engine wins over a stray shellx binary")
    func flutterWinsOverCLI() {
        let kind = SingleInstanceConflictPolicy.classifyExistingBundle(
            at: flutter,
            fileExists: files([
                "/Applications/ShellX.app/Contents/Frameworks/FlutterMacOS.framework",
                "/Applications/ShellX.app/Contents/Resources/bin/shellx",
            ])
        )
        #expect(kind == .olderShellX)
    }

    @Test("an unreported bundle path is unknown")
    func unknownPath() {
        #expect(SingleInstanceConflictPolicy.classifyExistingBundle(at: nil, fileExists: files([])) == .unknown)
    }

    @Test("an older ShellX is asked about, even with the replace override")
    func olderAsks() {
        for environment in [[:], [SingleInstanceConflictPolicy.allowReplacingEnvironmentKey: "1"]] {
            #expect(
                SingleInstanceConflictPolicy(environment: environment).action(
                    currentBundleURL: current,
                    existingBundleURL: flutter,
                    existingKind: .olderShellX
                ) == .askToQuitOlderShellX
            )
        }
    }

    @Test("another native ShellX keeps today's yield, and the override still replaces it")
    func nativeKeepsYield() {
        #expect(
            SingleInstanceConflictPolicy(environment: [:]).action(
                currentBundleURL: current, existingBundleURL: native, existingKind: .nativeShellX
            ) == .yieldToExisting
        )
        #expect(
            SingleInstanceConflictPolicy(environment: [:]).action(
                currentBundleURL: current, existingBundleURL: nil, existingKind: .unknown
            ) == .yieldToExisting
        )
        #expect(
            SingleInstanceConflictPolicy(environment: [SingleInstanceConflictPolicy.allowReplacingEnvironmentKey: "1"])
                .action(currentBundleURL: current, existingBundleURL: native, existingKind: .nativeShellX)
                == .replaceExisting
        )
    }

    @Test("an older ShellX launched while we run is left running")
    func duplicateLaunchOfOlderIsLeftAlone() {
        #expect(
            SingleInstanceConflictPolicy.duplicateLaunchAction(
                launchedBundleURL: flutter, currentBundleURL: current, launchedKind: .olderShellX
            ) == .leaveOlderShellXRunning
        )
    }

    @Test("a same-bundle relaunch is ignored and another native copy is terminated as before")
    func duplicateLaunchOfNative() {
        #expect(
            SingleInstanceConflictPolicy.duplicateLaunchAction(
                launchedBundleURL: URL(fileURLWithPath: "/Users/dev/Build/./ShellX DEV w1.app/", isDirectory: true),
                currentBundleURL: current,
                launchedKind: .nativeShellX
            ) == .ignoreSameBundle
        )
        #expect(
            SingleInstanceConflictPolicy.duplicateLaunchAction(
                launchedBundleURL: native, currentBundleURL: current, launchedKind: .nativeShellX
            ) == .terminateDuplicate
        )
        #expect(
            SingleInstanceConflictPolicy.duplicateLaunchAction(
                launchedBundleURL: nil, currentBundleURL: current, launchedKind: .unknown
            ) == .terminateDuplicate
        )
    }
}

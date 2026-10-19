import ShellXBrand

/// App-side mirror of ``ShellXFeatures`` for code that cannot import
/// ShellXBrand, chiefly the app-hosted test bundle: upstream tests of logic
/// parked behind a switch use `.enabled(if: ShellXSwitches.remoteMachines)` so
/// they come back on their own when Wave 2 flips it.
enum ShellXSwitches {
    /// Manaflow Cloud (sign-in, accounts, Cloud machines, billing, Pro). Off for good.
    static let cloud = ShellXFeatures.cloud
    /// CodeRouter. Off for good.
    static let codeRouter = ShellXFeatures.codeRouter
    /// ShellX's own remote machines and device mirroring (Wave 2).
    static let remoteMachines = ShellXFeatures.remoteMachines
}

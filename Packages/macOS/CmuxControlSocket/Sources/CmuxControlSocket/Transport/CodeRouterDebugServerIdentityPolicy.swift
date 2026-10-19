/// Validates the identity fields for a tagged Debug ShellX server.
public struct CodeRouterDebugServerIdentityPolicy {
    /// Creates a Debug server identity policy.
    public init() {}

    /// Tests whether the signing fields match the expected tagged ShellX build.
    ///
    /// - Parameters:
    ///   - identifier: The connected server's code-signing identifier.
    ///   - teamIdentifier: The connected server's signing team.
    ///   - expectedBundleIdentifier: The tagged bundle identifier selected by
    ///     the CLI environment.
    /// - Returns: `true` only for the exact expected company-signed Debug app.
    public func isAllowed(
        identifier: String?,
        teamIdentifier: String?,
        expectedBundleIdentifier: String?
    ) -> Bool {
        // `ShellXBrand.bundleID` / `.teamID` (this package does not link ShellXBrand).
        let taggedPrefix = "pro.shellx.desktop.debug."
        guard let expectedBundleIdentifier,
              expectedBundleIdentifier.hasPrefix(taggedPrefix),
              expectedBundleIdentifier.count > taggedPrefix.count,
              identifier == expectedBundleIdentifier,
              teamIdentifier == "W4RF3W4VTZ" else {
            return false
        }
        return true
    }
}

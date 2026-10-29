import Foundation
import Observation

/// Whether to offer the user a newer App Store version. The app calls `check()` at launch and each
/// time it comes to the front; the popup shows while `offered` is set. Later hides it until the next
/// check, so it comes back the next time the app opens. Never required: the app works on either
/// version.
@MainActor @Observable
public final class UpdatePrompt {
    /// The newer release to offer, or nil.
    public private(set) var offered: AppStoreRelease?

    @ObservationIgnored private let installedVersion: String
    @ObservationIgnored private let fetch: @Sendable () async throws -> Data
    @ObservationIgnored private var checking = false

    /// `fetch` returns the App Store's lookup answer (`AppStoreRelease.lookupURL`).
    public init(installedVersion: String, fetch: @escaping @Sendable () async throws -> Data) {
        self.installedVersion = installedVersion
        self.fetch = fetch
    }

    /// Asks the App Store once; a check while one is under way does nothing. A failed lookup (no
    /// network, the store did not answer) changes nothing and says nothing.
    public func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        guard let data = try? await fetch() else { return }
        let release = AppStoreRelease.parse(data)
        offered = release.flatMap { AppVersion.isNewer($0.version, than: installedVersion) ? $0 : nil }
    }

    /// The user picked Later, or went to the store: hide the popup until the next check.
    public func later() {
        offered = nil
    }
}

import Foundation
import Observation

/// Holds a `shellx-link://` link the system opened the app with (the Camera app, Safari) until a
/// signed-in screen takes it, so a link opened before sign-in still reaches the pairing sheet
/// afterwards. Only the newest link is kept, in memory only: it carries a one-time code.
@MainActor @Observable
public final class PairingInbox {
    public static let scheme = "shellx-link"

    private var held: String?

    public init() {}

    /// True while a link waits to be taken.
    public var hasLink: Bool { held != nil }

    /// Keeps `url` when it is a `shellx-link` link. Returns false (and keeps nothing) otherwise.
    @discardableResult
    public func receive(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.scheme else { return false }
        held = url.absoluteString
        return true
    }

    /// The waiting link, once.
    public func take() -> String? {
        defer { held = nil }
        return held
    }
}

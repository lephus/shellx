import Foundation

/// Display-only view of the currently signed-in cmux user.
///
/// Surface for the package's ``AccountSection`` to render an identity
/// card without depending on the host's auth package. The host wraps
/// its own user type (e.g. `CMUXAuthCore.CMUXAuthUser`) in an
/// ``AccountIdentity`` when it constructs the ``AccountFlow``
/// delegate.
public struct AccountIdentity: Sendable, Hashable {
    /// Stable identifier for the user (e.g. backend user id).
    public let id: String

    /// User-facing display name. May be empty.
    public let displayName: String

    /// Primary email address. May be empty if the auth provider
    /// doesn't surface one.
    public let email: String

    /// Optional avatar URL the host has resolved to a fetchable image.
    public let avatarURL: URL?

    /// Optional host-formatted line shown under the email when there is no
    /// display name, such as when the account last signed in.
    public let detail: String?

    public init(
        id: String,
        displayName: String,
        email: String,
        avatarURL: URL? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.detail = detail
    }
}

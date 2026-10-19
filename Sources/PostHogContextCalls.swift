import Foundation

/// The analytics call that sets context on later events, injectable so tests
/// observe it. ShellX links no PostHog SDK, so the live call drops the context. Person identity and groups (`identify`,
/// `group`, `reset`) are owned by the sign-in identity observer.
struct PostHogContextCalls: Sendable {
    var register: @Sendable ([String: Any]) -> Void

    static let live = PostHogContextCalls(
        register: { _ in }
    )
}

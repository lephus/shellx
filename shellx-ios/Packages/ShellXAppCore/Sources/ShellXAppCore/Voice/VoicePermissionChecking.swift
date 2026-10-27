import Foundation

/// The two permissions the mic needs.
public enum VoicePermission: Equatable, Sendable {
    case microphone
    case speech
}

/// Asks iOS for the mic's permissions. Each call asks the user when they were never asked, and
/// otherwise answers with what they chose.
public protocol VoicePermissionChecking: Sendable {
    /// True when `microphone()` or `speech()` would show the system prompt (never asked yet). The
    /// time a prompt stays up is not speech latency, so that press records no `firstWord` sample.
    func needsPrompt() async -> Bool
    func microphone() async -> Bool
    func speech() async -> Bool
}

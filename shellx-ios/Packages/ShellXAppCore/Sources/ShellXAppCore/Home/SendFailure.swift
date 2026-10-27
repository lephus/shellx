import Foundation

/// Why a message from the home screen did not reach its session.
public enum SendFailure: String, Codable, Sendable {
    /// The Mac no longer has that session.
    case notFound
    /// The session the message was started for is no longer running; it went nowhere else.
    case ended
    /// The session is busy and did not take the message.
    case busy
    /// The Mac could not type it in (or answered something this app does not know).
    case failed
    /// No answer from the Mac: the message may or may not have arrived.
    case noAnswer
}

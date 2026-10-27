import Foundation

/// Why a call to a Mac was not sent.
public enum LinkCallError: Error, Equatable {
    /// The Mac has no live, synced session right now. Nothing was sent.
    case offline(machineName: String)
    /// No paired Mac has that id.
    case unknownMachine
}

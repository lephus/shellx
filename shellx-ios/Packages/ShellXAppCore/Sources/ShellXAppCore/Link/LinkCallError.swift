import Foundation

/// Why a call to a Mac was not sent.
public enum LinkCallError: Error, Equatable {
    /// The Mac has no live, synced session right now. Nothing was sent.
    case offline(machineName: String)
    /// The Mac removed this iPhone, or its key changed: nothing was sent, and nothing can be until
    /// it is paired again.
    case needsPairing(machineName: String)
    /// No paired Mac has that id.
    case unknownMachine
}

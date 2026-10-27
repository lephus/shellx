import Foundation

/// Something that keeps data on this phone for the signed-in account (history, caches) and must
/// forget it on sign-out or when another account signs in.
public protocol LocalDataWiping: Sendable {
    func wipe() async
}

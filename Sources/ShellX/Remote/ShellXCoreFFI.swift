import Foundation

/// ShellX: the app's one door into shellx-core, the statically linked Rust core
/// (C ABI in shellx-core/include/shellx_core.h, included by the bridging header).
///
/// `call` blocks on network and disk work inside the core, so it must never run on
/// the main thread; callers hop to a detached task or their own queue. The core is
/// thread-safe and this type holds no state.
final class ShellXCoreFFI: @unchecked Sendable {
    static let shared = ShellXCoreFFI()

    enum CallError: Error, Equatable {
        /// The method name or the JSON input is not NUL-free UTF-8.
        case invalidInput
        /// The core returned no envelope (the C ABI promises it never does).
        case noResponse
    }

    private init() {}

    /// Calls `method` with UTF-8 JSON `json` and returns the core's JSON envelope,
    /// `{"ok": ...}` or `{"error": {"code": ..., "message": ...}}`.
    func call(method: String, json: Data) throws -> Data {
        #if DEBUG
        assert(!Thread.isMainThread, "ShellXCoreFFI.call blocks; never call it on the main thread")
        #endif
        guard let input = String(data: json, encoding: .utf8),
              !method.utf8.contains(0), !input.utf8.contains(0) else {
            throw CallError.invalidInput
        }
        let result: UnsafeMutablePointer<CChar>? = method.withCString { methodPtr in
            input.withCString { inputPtr in
                shellx_core_call(methodPtr, inputPtr)
            }
        }
        guard let result else { throw CallError.noResponse }
        defer { shellx_core_free(result) }
        return Data(bytes: result, count: strlen(result))
    }
}

import CryptoKit
import Foundation

/// The 32-byte secret that lives only in the share URL fragment.
public struct ShareSecret: Sendable, Equatable {
    private let bytes: Data

    public static func random() -> ShareSecret {
        ShareSecret(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    private init(bytes: Data) { self.bytes = bytes }

    /// Parses base64url without padding; nil unless it decodes to exactly 32 bytes.
    public init?(base64url: String) {
        guard let data = Data(shareBase64URL: base64url), data.count == 32 else { return nil }
        self.bytes = data
    }

    public var base64url: String { bytes.shareBase64URLString }

    /// HKDF-SHA256, salt = UTF-8 of the share id without dash. `shareID` may carry the display dash.
    public func keys(shareID: String) -> ShareKeys {
        let salt = Data(shareID.replacingOccurrences(of: "-", with: "").utf8)
        let ikm = SymmetricKey(data: bytes)
        func derive(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data(info.utf8), outputByteCount: 32)
        }
        let access = derive("shellx-share/1 access").withUnsafeBytes { Data($0).shareBase64URLString }
        return ShareKeys(hostToViewer: derive("shellx-share/1 host->viewer"),
                         viewerToHost: derive("shellx-share/1 viewer->host"), access: access)
    }
}

public struct ShareKeys: Sendable {
    public let hostToViewer: SymmetricKey
    public let viewerToHost: SymmetricKey
    /// base64url, sent to the API as proof of knowing the fragment.
    public let access: String
}

extension Data {
    init?(shareBase64URL string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !s.contains("=") else { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }

    var shareBase64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

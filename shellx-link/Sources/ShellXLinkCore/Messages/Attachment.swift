import Foundation

/// What an upload is (PROTOCOL.md section 5, "Attachments"). It tells the host how to store it:
/// an image is saved as a pasted image, a file under a name the host sanitises.
public enum AttachmentKind: LinkWireEnum {
    case image
    case file
    /// A kind this version does not know; a host that does not know it can refuse the upload.
    case other(String)

    public init(wire: String) {
        switch wire {
        case "image": self = .image
        case "file": self = .file
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .image: return "image"
        case .file: return "file"
        case let .other(raw): return raw
        }
    }
}

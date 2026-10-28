import Foundation
import ShellXLinkCore

/// A photo or file waiting in the composer, sent with the next message (PROTOCOL.md section 5,
/// "Attachments"): its bytes as picked, and the name the Mac is told (only a label: the Mac
/// sanitises it). Never logged: neither the bytes nor the name.
public struct OutgoingAttachment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: AttachmentKind
    public let name: String
    public let data: Data

    public init(id: UUID = UUID(), kind: AttachmentKind, name: String, data: Data) {
        self.id = id
        self.kind = kind
        self.name = name
        self.data = data
    }
}

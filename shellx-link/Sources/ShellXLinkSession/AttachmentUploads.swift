import CryptoKit
import Foundation
import ShellXLinkCore

/// The SHA-256 of `data`: the 32 bytes `attach.end` carries.
func sha256Digest(of data: Data) -> Data {
    Data(SHA256.hash(data: data))
}

/// A refusal of an `attach.*` call or of the attachments of a `chat.send`: sent as `error` with this `code`.
struct AttachmentRefusal: Error, Equatable {
    let code: String
    let message: String

    static func badRequest(_ message: String) -> AttachmentRefusal {
        AttachmentRefusal(code: "bad_request", message: message)
    }

    /// The `error` frame that answers call `callId`.
    func frame(answering callId: String) -> LinkMessage {
        .error(code: code, message: message, callId: callId)
    }
}

/// The uploads of one Link session that no `chat.send` has used yet (PROTOCOL.md section 5, "Attachments"). It is
/// a value in the host's session loop, so it lives and dies with the session: an id means nothing in another one.
///
/// Bytes stay in memory: at most `ShellXLink.maxPendingUploads` finished uploads of at most
/// `ShellXLink.maxAttachmentBytes` each, plus the one going up. Nothing here logs a name or any bytes.
///
/// A phone uploads one attachment at a time and runs a message's uploads and its `chat.send` with no other message's
/// uploads in between, so no upload outlives its usefulness by holding a place:
/// * an `attach.begin` first drops every upload that has not had its `attach.end` (one the phone gave up on);
/// * an `attach.begin` that would make a sixth unsent upload drops the one that finished first: an upload left by a
///   message that failed, never one of the message going up (it has at most 5, and they finished last);
/// * once `ShellXLink.unsentUploadLifetime` passes with no `attach.*` call accepted, every upload is dropped. This
///   is checked lazily, at each `attach.*` call and `chat.send`, against the injected clock.
struct AttachmentUploads {
    private struct Upload {
        let kind: AttachmentKind
        let name: String
        let size: Int
        var data = Data()
        /// The order `attach.end` accepted the digest in; nil until then. Only a finished upload can be named by a
        /// `chat.send`.
        var finishOrder: Int?

        var finished: Bool { finishOrder != nil }
    }

    private var uploads: [String: Upload] = [:]
    /// When the host last accepted an `attach.*` call of this session; nil before the first one.
    private var lastAccepted: ContinuousClock.Instant?
    private var finishedCount = 0
    private let now: @Sendable () -> ContinuousClock.Instant

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Answers one `attach.begin`, `attach.chunk` or `attach.end` from the phone: the host's reply, or an `error`
    /// that carries the call's `call_id`.
    mutating func serve(_ message: LinkMessage) -> LinkMessage {
        dropIfIdle()
        let answer = answer(message)
        if case .error = answer {} else { lastAccepted = now() }
        return answer
    }

    private mutating func answer(_ message: LinkMessage) -> LinkMessage {
        switch message {
        case let .attachBegin(callId, kind, name, size):
            do throws(AttachmentRefusal) {
                return .attachReady(callId: callId, attachmentId: try begin(kind: kind, name: name, size: size))
            } catch {
                return error.frame(answering: callId)
            }
        case let .attachChunk(callId, attachmentId, offset, data):
            do throws(AttachmentRefusal) {
                let received = try append(data, at: offset, to: attachmentId)
                return .attachChunkResult(callId: callId, attachmentId: attachmentId, received: received)
            } catch {
                return error.frame(answering: callId)
            }
        case let .attachEnd(callId, attachmentId, sha256):
            do throws(AttachmentRefusal) {
                try finish(attachmentId, sha256: sha256)
                return .attachEndResult(callId: callId, attachmentId: attachmentId)
            } catch {
                return error.frame(answering: callId)
            }
        default:
            return .error(code: "bad_request", message: "not an upload call", callId: nil)
        }
    }

    /// The uploads `ids` name, as attachments in that order, removed from the session. All or none: when any id
    /// fails the checks nothing is removed. The checks are PROTOCOL.md section 5's: at most
    /// `ShellXLink.maxAttachmentsPerMessage` ids, each held, finished, and named once.
    mutating func take(_ ids: [String]) throws(AttachmentRefusal) -> [ChatAttachment] {
        dropIfIdle()
        guard ids.count <= ShellXLink.maxAttachmentsPerMessage else {
            throw .badRequest("at most \(ShellXLink.maxAttachmentsPerMessage) attachments per message")
        }
        guard Set(ids).count == ids.count else { throw .badRequest("an attachment is named twice") }
        var taken: [ChatAttachment] = []
        for id in ids {
            guard let upload = uploads[id], upload.finished else {
                throw .badRequest("an attachment is not held, or not finished")
            }
            taken.append(ChatAttachment(kind: upload.kind, name: upload.name, data: upload.data))
        }
        for id in ids { uploads[id] = nil }
        return taken
    }

    private mutating func begin(kind: AttachmentKind, name: String, size: Int) throws(AttachmentRefusal) -> String {
        // One upload at a time: whatever is not finished was given up, and must not hold a place.
        uploads = uploads.filter { $0.value.finished }
        switch kind {
        case .image, .file: break
        case .other: throw .badRequest("this host takes only image and file attachments")
        }
        guard size >= 1 else { throw .badRequest("size must be at least 1") }
        guard size <= ShellXLink.maxAttachmentBytes else {
            throw AttachmentRefusal(code: "too_large", message: "size is above \(ShellXLink.maxAttachmentBytes) bytes")
        }
        // Full: the upload that finished first makes room. It is never one of the message going up, whose
        // uploads finished after it and number at most `maxAttachmentsPerMessage`.
        while uploads.count >= ShellXLink.maxPendingUploads,
              let oldest = uploads.min(by: { ($0.value.finishOrder ?? 0) < ($1.value.finishOrder ?? 0) })?.key
        {
            uploads[oldest] = nil
        }
        let id = UUID().uuidString
        uploads[id] = Upload(kind: kind, name: name, size: size)
        return id
    }

    /// Adds a chunk and returns the bytes held. A chunk that breaks a rule is not applied, and the upload stays.
    private mutating func append(_ chunk: Data, at offset: Int, to id: String) throws(AttachmentRefusal) -> Int {
        // Scalars only: a copy of the upload would keep a second reference to the bytes, and the append below
        // would then copy all of them for every chunk.
        guard let state = uploads[id].map({ (held: $0.data.count, size: $0.size, finished: $0.finished) }),
              !state.finished
        else { throw .badRequest("no such unfinished upload") }
        guard offset == state.held else { throw .badRequest("offset must be \(state.held)") }
        guard (1...ShellXLink.maxAttachmentChunkBytes).contains(chunk.count) else {
            throw .badRequest("a chunk is 1 to \(ShellXLink.maxAttachmentChunkBytes) bytes")
        }
        guard state.held + chunk.count <= state.size else { throw .badRequest("more bytes than size") }
        uploads[id]?.data.append(chunk)
        return state.held + chunk.count
    }

    /// Checks the length and the digest. Either failing drops the upload.
    private mutating func finish(_ id: String, sha256: Data) throws(AttachmentRefusal) {
        guard let upload = uploads[id], !upload.finished else { throw .badRequest("no such unfinished upload") }
        guard upload.data.count == upload.size else {
            uploads[id] = nil
            throw .badRequest("attach.end before size bytes arrived")
        }
        guard sha256Digest(of: upload.data) == sha256 else {
            uploads[id] = nil
            throw .badRequest("the digest does not match the bytes")
        }
        finishedCount += 1
        uploads[id]?.finishOrder = finishedCount
    }

    /// Drops every upload once `ShellXLink.unsentUploadLifetime` has passed since the last accepted `attach.*` call.
    private mutating func dropIfIdle() {
        guard let lastAccepted, now() - lastAccepted > ShellXLink.unsentUploadLifetime else { return }
        uploads.removeAll()
        self.lastAccepted = nil
    }
}

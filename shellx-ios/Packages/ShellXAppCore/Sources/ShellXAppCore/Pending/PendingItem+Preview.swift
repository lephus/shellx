import Foundation
import ShellXLinkCore

extension PendingItem {
    /// Keys of a tool's input that say best what the call does, most telling first: Bash's
    /// `command`, the file of Read/Edit/Write, the address of WebFetch, the pattern of Grep/Glob.
    private static let telling = ["command", "file_path", "notebook_path", "url", "pattern", "path", "query"]

    /// The text under a card's header, for display only (PROTOCOL.md section 6: never the complete
    /// input):
    /// - permission: the tool input's most telling value (the command, the file), or the preview as
    ///   it came when it is not a JSON object (a preview cut at 8192 bytes no longer parses);
    /// - question: every question's prompt, one per line;
    /// - plan: the plan.
    public var previewText: String? {
        switch kind {
        case .permission:
            return toolInputPreview.map(Self.tellingValue)
        case .question:
            let prompts = (questions ?? []).map(\.prompt)
            return prompts.isEmpty ? nil : prompts.joined(separator: "\n")
        case .exitPlan:
            return planPreview
        case .other:
            return toolInputPreview ?? planPreview
        }
    }

    /// The tool input's fields for the full view ("Show more"): the most telling first, then the
    /// others by name; a value that is not a string as compact JSON. Nil when the preview is not a
    /// JSON object (then it is shown as it came).
    public var previewFields: [(key: String, value: String)]? {
        guard let preview = toolInputPreview, let object = Self.object(preview) else { return nil }
        let others = object.keys.filter { !Self.telling.contains($0) }.sorted()
        let keys = Self.telling.filter { object[$0] != nil } + others
        return keys.compactMap { key in object[key].map { (key, Self.text($0)) } }
    }

    /// True when `text` may have been cut by the host (PROTOCOL.md section 6): it ends within one
    /// character of the 8192-byte preview limit or of the 1024-byte step for oversize frames.
    public static func previewMayBeCut(_ text: String) -> Bool {
        let bytes = text.utf8.count
        return [maxPreviewBytes, 1024].contains { bytes <= $0 && bytes > $0 - 4 }
    }

    private static func object(_ preview: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(preview.utf8)) as? [String: Any]
    }

    private static func text(_ value: Any) -> String {
        if let string = value as? String { return string }
        let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options) else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func tellingValue(_ preview: String) -> String {
        guard let object = object(preview) else { return preview }
        for key in telling {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return preview
    }
}

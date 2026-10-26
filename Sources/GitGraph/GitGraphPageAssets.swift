import CmuxAgentChat
import Foundation

/// Reads the bundled files that ``GitGraphURLSchemeHandler`` serves for the Git
/// Graph page.
///
/// Only a file under ``root`` with a type the page loads is served. The build's
/// "Compress Markdown Viewer Assets" phase replaces every `.js` and `.mjs` with a
/// zlib `.deflate` sibling, so a missing script is read by inflating that sibling.
/// Reading touches the file system; call it off the main actor.
struct GitGraphPageAssets: Sendable {
    /// A file's bytes and the MIME type it is served with.
    struct Asset: Equatable, Sendable {
        let data: Data
        let mimeType: String
    }

    /// Why a request has no asset.
    enum Failure: Error, Equatable {
        /// Not a page URL, or a path that is not a plain relative path under the root.
        case badURL
        /// No such file, or a type the page does not load.
        case notFound
        /// The file exists but could not be read or inflated.
        case unreadable
    }

    private static let maximumFileByteCount = 32 * 1024 * 1024
    private static let deflatedExtensions: Set<String> = ["js", "mjs"]

    /// The folder the page's files are served from, standardized.
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// The page's folder in `bundle`'s resources, or nil when it has none.
    static func bundled(in bundle: Bundle = .main) -> GitGraphPageAssets? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        return GitGraphPageAssets(
            root: resourceURL.appendingPathComponent("markdown-viewer/webviews-app", isDirectory: true)
        )
    }

    /// The MIME type for a file extension the page loads, or nil for any other.
    static func mimeType(forPathExtension pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "woff2": "font/woff2"
        case "png": "image/png"
        default: nil
        }
    }

    /// The asset `requestURL` names: the file itself, or for a script whose file
    /// is missing, its inflated `.deflate` sibling.
    func asset(for requestURL: URL) throws -> Asset {
        let file = try fileURL(for: requestURL)
        guard let mimeType = Self.mimeType(forPathExtension: file.pathExtension) else {
            throw Failure.notFound
        }
        if let data = try readRegularFile(at: file) {
            return Asset(data: data, mimeType: mimeType)
        }
        guard Self.deflatedExtensions.contains(file.pathExtension.lowercased()),
              let compressed = try readRegularFile(at: file.appendingPathExtension("deflate")) else {
            throw Failure.notFound
        }
        guard let data = Data.inflateMarkdownViewerAsset(compressed) else { throw Failure.unreadable }
        return Asset(data: data, mimeType: mimeType)
    }

    /// The file under ``root`` that a `shellx-git-graph://app/` URL names. Its
    /// query and fragment are ignored.
    func fileURL(for requestURL: URL) throws -> URL {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              components.scheme == GitGraphURLSchemeHandler.scheme,
              components.host == GitGraphURLSchemeHandler.host,
              components.port == nil, components.user == nil, components.password == nil else {
            throw Failure.badURL
        }
        return try fileURL(forRequestPath: components.percentEncodedPath)
    }

    /// The file under ``root`` for a URL's percent-encoded path, such as
    /// `/chunks/main.mjs`.
    ///
    /// Each decoded component must be a plain name: an empty component (`//`, an
    /// absolute path), `.`, `..` or a backslash is rejected, and so is a result
    /// that standardizes to anything outside ``root``.
    func fileURL(forRequestPath percentEncodedPath: String) throws -> URL {
        guard percentEncodedPath.hasPrefix("/"),
              let path = percentEncodedPath.removingPercentEncoding else {
            throw Failure.badURL
        }
        let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        let isPlain: (Substring) -> Bool = { component in
            !component.isEmpty && component != "." && component != ".."
                && !component.contains("\\") && !component.contains("\0")
        }
        guard !components.isEmpty, components.allSatisfy(isPlain) else { throw Failure.badURL }
        let file = root.appendingPathComponent(components.joined(separator: "/"), isDirectory: false)
            .standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { throw Failure.badURL }
        return file
    }

    /// The bytes of the regular file at `url`, or nil when nothing is there.
    private func readRegularFile(at url: URL) throws -> Data? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { throw Failure.notFound }
        // A link inside the bundle must not reach a file outside it.
        let resolvedPath = url.resolvingSymlinksInPath().path
        guard resolvedPath.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw Failure.badURL }
        let size = (try? FileManager.default.attributesOfItem(atPath: resolvedPath)[.size] as? Int) ?? 0
        guard size <= Self.maximumFileByteCount else { throw Failure.unreadable }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw Failure.unreadable
        }
    }
}

import SwiftUI
import UIKit

/// Renders a SwiftUI view the way the app shows it, for render tests (test-only).
///
/// The view is hosted in a 393 x 852 pt `UIWindow` and drawn with `drawHierarchy`, once with the
/// light and once with the dark interface style. `ImageRenderer` is not used because it leaves
/// `List` and `TextField` blank. When `SHELLX_SNAPSHOT_DIR` is set (`dev.sh screenshots`), each
/// image is also written there as `<name>-<light|dark>-<language>.png`.
///
/// Another phone or a phone on its side: pass its `size` and its `safeArea`. The window is then that size
/// and the view gets exactly those safe-area insets instead of the simulator's own.
@MainActor
struct SnapshotWriter {
    static let size = CGSize(width: 393, height: 852)

    /// Returns the light image, then the dark one. `settle` is how long the run loop runs before drawing,
    /// for a view that loads something as it appears.
    func write(
        _ view: some View, name: String, size: CGSize = SnapshotWriter.size, safeArea: EdgeInsets? = nil,
        settle: TimeInterval = 0.05
    ) throws -> [UIImage] {
        let directory = ProcessInfo.processInfo.environment["SHELLX_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var images: [UIImage] = []
        for (style, label) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let image = render(view, style: style, size: size, safeArea: safeArea, settle: settle)
            images.append(image)
            if let directory {
                try save(image, to: URL(fileURLWithPath: directory), name: "\(name)-\(label)-\(language).png")
            }
        }
        return images
    }

    private func render(
        _ view: some View, style: UIUserInterfaceStyle, size: CGSize, safeArea: EdgeInsets?, settle: TimeInterval
    ) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let window = makeWindow(frame: bounds)
        window.overrideUserInterfaceStyle = style
        let host: UIViewController
        if let safeArea {
            // The window's own insets (the simulator's island and home indicator) are dropped for the given ones.
            let controller = UIHostingController(rootView: view.safeAreaPadding(safeArea))
            controller.safeAreaRegions = []
            host = controller
        } else {
            host = UIHostingController(rootView: view)
        }
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let SwiftUI finish its first update (fonts, asset images, scaled metrics) before drawing.
        RunLoop.main.run(until: Date().addingTimeInterval(settle))

        // The default format renders at the screen's scale.
        let image = UIGraphicsImageRenderer(bounds: bounds, format: UIGraphicsImageRendererFormat()).image { _ in
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }

    private func makeWindow(frame: CGRect) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
        window.frame = frame
        return window
    }

    private func save(_ image: UIImage, to directory: URL, name: String) throws {
        guard let data = image.pngData() else { throw SnapshotWriterError.encodingFailed(name) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}

enum SnapshotWriterError: Error {
    case encodingFailed(String)
}

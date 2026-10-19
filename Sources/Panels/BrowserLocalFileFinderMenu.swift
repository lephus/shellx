import Foundation
import SwiftUI
import ShellXIcons

/// Adds the shared Finder reveal action when the browser is displaying a local file.
struct BrowserLocalFileFinderMenu: View {
    let fileURL: URL?

    var body: some View {
        if let fileURL, fileURL.isFileURL {
            Divider()
            Button {
                FileExternalOpenAction.revealInFinder(fileURL: fileURL)
            } label: {
                ShellXLabel(
                    FileExternalOpenText.revealInFinder,
                    icon: "folder"
                )
            }
            .accessibilityIdentifier("BrowserRevealLocalFileInFinder")
        }
    }
}

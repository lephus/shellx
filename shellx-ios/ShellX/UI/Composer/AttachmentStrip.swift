import ImageIO
import ShellXAppCore
import SwiftUI
import UIKit

/// The attachments waiting in the composer: a row of 56 pt tiles above the field, a photo as its
/// thumbnail and a file as a `doc` icon over its name, then a spinner tile for each pick still
/// being read. Each tile has an ✕ that takes it out, off while the message is being sent
/// (`locked`).
struct AttachmentStrip: View {
    static let tileSide: CGFloat = 56

    @Binding var attachments: [OutgoingAttachment]
    let locked: Bool
    /// Picks still being read.
    var loading = 0
    /// One was taken out.
    let removed: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    tile(attachment)
                }
                ForEach(0..<max(loading, 0), id: \.self) { _ in
                    ProgressView()
                        .frame(width: Self.tileSide, height: Self.tileSide)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel(Text(LocalizedStringResource("composer.attach.loading")))
                }
            }
            // Room for the ✕ buttons, which stand out of the tiles' corners.
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .scrollClipDisabled()
        .opacity(locked ? 0.6 : 1)
        .accessibilityIdentifier("composer.attachments")
    }

    private func tile(_ attachment: OutgoingAttachment) -> some View {
        content(attachment)
            .frame(width: Self.tileSide, height: Self.tileSide)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button {
                    attachments.removeAll { $0.id == attachment.id }
                    removed()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 20, height: 20)
                        .background(Color(uiColor: .secondaryLabel), in: Circle())
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 12, y: -12)
                .disabled(locked)
                .accessibilityLabel(Text(verbatim: String(localized: "composer.attachment.remove \(attachment.name)")))
            }
    }

    @ViewBuilder private func content(_ attachment: OutgoingAttachment) -> some View {
        if attachment.kind == .image, let thumbnail = AttachmentThumbnails.image(for: attachment) {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .accessibilityLabel(Text(verbatim: attachment.name))
        } else {
            VStack(spacing: 3) {
                Image(systemName: attachment.kind == .image ? "photo" : "doc")
                    .font(.title3)
                    .foregroundStyle(Color("AccentText"))
                Text(verbatim: attachment.name)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: attachment.name))
        }
    }
}

/// Small thumbnails of the photos in the composer, made once each with ImageIO (never the full
/// image in memory) and kept while memory allows. Only for display: what is sent is untouched.
@MainActor
enum AttachmentThumbnails {
    /// Pixels on the long side: a 56 pt tile at 3x, with a little to spare.
    static let maxPixelSize = 200
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for attachment: OutgoingAttachment) -> UIImage? {
        let key = attachment.id as NSUUID
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithData(attachment.data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }
}

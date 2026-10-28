import PhotosUI
import ShellXAppCore
import SwiftUI
import UniformTypeIdentifiers

/// The composer's "+": a menu of Photos (the system photo picker, for as many as there is room
/// left) and Files (the Files picker, several at once). What is picked is read off the main actor
/// (`AttachmentPreparer`) and added in the order picked, up to
/// `ShellXLink.maxAttachmentsPerMessage`. What cannot be added says why through `note`, which a new
/// pick clears.
struct AttachMenu: View {
    @Binding var attachments: [OutgoingAttachment]
    /// The button's side, the same as the send button's.
    let side: CGFloat
    /// The composer's red line: why something picked was not added; nil clears it.
    let note: (String?) -> Void

    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var pickedPhotos: [PhotosPickerItem] = []

    /// How many more the message can carry.
    private var room: Int { max(ShellXLink.maxAttachmentsPerMessage - attachments.count, 0) }

    var body: some View {
        Menu {
            Button {
                note(nil)
                showsPhotos = true
            } label: {
                Label(String(localized: "composer.attach.photos"), systemImage: "photo.on.rectangle")
            }
            Button {
                note(nil)
                showsFiles = true
            } label: {
                Label(String(localized: "composer.attach.files"), systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color("AccentText"))
                .frame(width: side, height: side)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        }
        .disabled(room == 0)
        .opacity(room == 0 ? 0.4 : 1)
        .accessibilityLabel(Text(LocalizedStringResource("composer.attach")))
        .accessibilityIdentifier("composer.attach")
        // 0 would mean "no limit" to the picker; the menu is off then anyway.
        .photosPicker(
            isPresented: $showsPhotos, selection: $pickedPhotos, maxSelectionCount: max(room, 1),
            matching: .images, preferredItemEncoding: .compatible)
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            addFiles(urls)
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            addPhotos(items)
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                let types = item.supportedContentTypes
                let taken = attachments.map(\.name)
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw AttachmentPreparer.Failure.unreadable(
                            name: AttachmentPreparer.photoName(for: Data(), contentTypes: types, taken: taken))
                    }
                    let attachment = try await Task.detached(priority: .userInitiated) {
                        try AttachmentPreparer.image(
                            data: data, name: AttachmentPreparer.photoName(for: data, contentTypes: types, taken: taken))
                    }.value
                    add(attachment)
                } catch {
                    let name = AttachmentPreparer.photoName(for: Data(), contentTypes: types, taken: taken)
                    note((error as? AttachmentPreparer.Failure ?? .unreadable(name: name)).message)
                }
            }
        }
    }

    private func addFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                do {
                    let attachment = try await Task.detached(priority: .userInitiated) {
                        try AttachmentPreparer.file(at: url)
                    }.value
                    add(attachment)
                } catch {
                    note((error as? AttachmentPreparer.Failure ?? .unreadable(name: url.lastPathComponent)).message)
                }
            }
        }
    }

    /// Adds one picked attachment, unless the message already carries as many as it can.
    private func add(_ attachment: OutgoingAttachment) {
        guard attachments.count < ShellXLink.maxAttachmentsPerMessage else {
            note(String(localized: "composer.attach.tooMany"))
            return
        }
        attachments.append(attachment)
    }
}

import PhotosUI
import ShellXAppCore
import SwiftUI
import UniformTypeIdentifiers
import os

/// The composer's "+": a menu of Photos (the system photo picker, for as many as there is room
/// left) and Files (the Files picker, several at once). What is picked is read off the main actor
/// (`AttachmentPreparer`) and added in the order picked, up to
/// `ShellXLink.maxAttachmentsPerMessage`. What cannot be added says why through `note`, which a new
/// pick clears; so does a Files picker that fails to hand over what was picked. `picks` holds the
/// picks still being read, from the moment the picker closes: the composer holds Send until none is
/// left, so no picked photo arrives after its message left, and each one's ✕ cancels it.
struct AttachMenu: View {
    @Binding var attachments: [OutgoingAttachment]
    /// Picks still being read.
    let picks: PendingPicks
    /// The button's side, the same as the send button's.
    let side: CGFloat
    /// The composer's red line: why something picked was not added; nil clears it.
    let note: (String?) -> Void

    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var pickedPhotos: [PhotosPickerItem] = []

    /// How many more the message can carry; a pick still being read holds its place.
    private var room: Int { max(ShellXLink.maxAttachmentsPerMessage - attachments.count - picks.count, 0) }

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
            switch result {
            case let .success(urls):
                addFiles(urls)
            case let .failure(error):
                // The reason, never a name: the picker failed to hand over what was picked.
                let reason = error as NSError
                Self.log.notice("attach_pick_failed domain=\(reason.domain, privacy: .public) code=\(reason.code)")
                note(String(localized: "composer.attach.pickFailed"))
            }
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            addPhotos(items)
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        picks.read(items.map { item in { try await loadPhoto(item) } }, done: received)
    }

    private func addFiles(_ urls: [URL]) {
        picks.read(urls.map { url in { try await AttachmentPreparer.readFile(at: url) } }, done: received)
    }

    /// One picked photo, as picked. Named when its read starts, after what the composer holds then,
    /// so photos read one after another get distinct names. Throws `AttachmentPreparer.Failure`.
    private func loadPhoto(_ item: PhotosPickerItem) async throws -> OutgoingAttachment {
        let types = item.supportedContentTypes
        let taken = attachments.map(\.name)
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AttachmentPreparer.Failure.unreadable(
                    name: AttachmentPreparer.photoName(for: Data(), contentTypes: types, taken: taken))
            }
            return try await Task.detached(priority: .userInitiated) {
                try AttachmentPreparer.image(
                    data: data, name: AttachmentPreparer.photoName(for: data, contentTypes: types, taken: taken))
            }.value
        } catch let failure as AttachmentPreparer.Failure {
            throw failure
        } catch {
            throw AttachmentPreparer.Failure.unreadable(
                name: AttachmentPreparer.photoName(for: Data(), contentTypes: types, taken: taken))
        }
    }

    /// A pick's read ended (a cancelled pick never gets here).
    private func received(_ result: Result<OutgoingAttachment, any Error>) {
        switch result {
        case let .success(attachment):
            add(attachment)
        case let .failure(error):
            note((error as? AttachmentPreparer.Failure)?.message ?? String(localized: "composer.attach.pickFailed"))
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

    private static let log = Logger(subsystem: "com.shellx.app", category: "attachments")
}

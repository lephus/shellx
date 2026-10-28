import ShellXAppCore
import SwiftUI

/// "Rename Workspace": a field filled with the current name, Cancel and Save. Save is off while the
/// name, trimmed, is empty (an empty name would only mean "go back to the automatic one", which
/// this sheet does not offer).
struct WorkspaceRenameSheet: View {
    /// The most characters of a name (`WorkspaceTitle.maxCharacters`).
    static let maxLength = WorkspaceTitle.maxCharacters

    let current: String
    /// Gets the trimmed name.
    let save: (String) -> Void
    let cancel: () -> Void

    @State private var title: String
    @FocusState private var focused: Bool

    init(current: String, save: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.current = current
        self.save = save
        self.cancel = cancel
        _title = State(initialValue: String(current.prefix(Self.maxLength)))
    }

    /// The name as sent (`WorkspaceTitle.cleaned(_:)`).
    static func cleaned(_ title: String) -> String {
        WorkspaceTitle.cleaned(title)
    }

    static func canSave(_ title: String) -> Bool {
        WorkspaceTitle.canSave(title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "workspaces.rename.placeholder"), text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: title) { _, new in
                        if new.count > Self.maxLength { title = String(new.prefix(Self.maxLength)) }
                    }
                    .accessibilityIdentifier("workspace.rename.field")
                    .listRowBackground(Color.appSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(String(localized: "workspaces.rename.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "workspaces.rename.save"), action: commit)
                        .disabled(!Self.canSave(title))
                        .accessibilityIdentifier("workspace.rename.save")
                }
            }
        }
        .presentationDetents([.height(220)])
        .task { focused = true }
    }

    private func commit() {
        guard Self.canSave(title) else { return }
        save(Self.cleaned(title))
    }
}

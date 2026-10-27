import ShellXAppCore
import SwiftUI

/// "Your Macs", fed by the hub, with the pending cards on top (until the main screen takes them).
struct MachinesView: View {
    let hub: MachineHub
    let center: DecisionCenter
    /// Opens the pairing sheet.
    let pair: () -> Void

    @State private var route: PendingRoute?

    var body: some View {
        MachineList(
            items: hub.machines.map { MachineListItem(id: $0.id, name: $0.name, state: $0.state) },
            defaultID: hub.defaultMachineID,
            makeDefault: { hub.defaultMachineID = $0 },
            unpair: { try await hub.unpair(machineID: $0) },
            pair: pair
        ) {
            PendingCardsSection(hub: hub, center: center, route: $route)
        }
        .sheet(item: $route) { route in
            PendingSheetHost(route: route, close: { self.route = nil })
        }
        // The center follows the hub's whole list here, outside any body; the cards only read it.
        .onAppear { center.sync(hub.pendingItems) }
        .onChange(of: hub.pendingItems) { _, items in center.sync(items) }
    }
}

/// One row's data, copied from a `MachineModel`.
struct MachineListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let state: MachineLinkState

    /// "Make Default" is offered unless the Mac is already the default, or cannot take messages
    /// until it is paired again (revoked, key changed).
    func offersMakeDefault(defaultID: String?) -> Bool {
        id != defaultID && state.canBeDefault
    }
}

/// The list of paired Macs with its actions; no hub, so render tests can show every state.
/// `header` goes above the Macs (the pending cards).
///
/// Each row offers "Make Default" and "Unpair" from its context menu and its swipe actions.
/// Unpairing asks first; removing a Mac that already removed this iPhone does not.
struct MachineList<Header: View>: View {
    let items: [MachineListItem]
    let defaultID: String?
    let makeDefault: (String) -> Void
    let unpair: (String) async throws -> Void
    let pair: () -> Void
    let header: Header

    init(
        items: [MachineListItem], defaultID: String?, makeDefault: @escaping (String) -> Void,
        unpair: @escaping (String) async throws -> Void, pair: @escaping () -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.items = items
        self.defaultID = defaultID
        self.makeDefault = makeDefault
        self.unpair = unpair
        self.pair = pair
        self.header = header()
    }

    @State private var confirming: MachineListItem?
    @State private var working: Set<String> = []
    @State private var failed: MachineListItem?

    var body: some View {
        List {
            header
            Section {
                ForEach(items) { item in
                    MachineRow(
                        name: item.name, state: item.state, isDefault: item.id == defaultID,
                        pairAgain: pair, remove: { unpairNow(item) }
                    )
                    .disabled(working.contains(item.id))
                    .contextMenu { menu(for: item) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipe(for: item) }
                }
            } footer: {
                Text(LocalizedStringResource("machines.footer"))
            }
        }
        .navigationTitle(String(localized: "machines.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: pair) {
                    Label(String(localized: "pairing.title"), systemImage: "plus")
                }
                .accessibilityIdentifier("machines.pair")
            }
        }
        .alert(
            confirming.map { String(localized: "machines.unpair.title \($0.name)") } ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { item in
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "machines.unpair"), role: .destructive) { unpairNow(item) }
        } message: { _ in
            Text(LocalizedStringResource("machines.unpair.message"))
        }
        .alert(
            String(localized: "machines.unpair.failed.title"),
            isPresented: Binding(get: { failed != nil }, set: { if !$0 { failed = nil } }),
            presenting: failed
        ) { _ in
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { item in
            Text(verbatim: String(localized: "machines.unpair.failed.message \(item.name)"))
        }
    }

    @ViewBuilder private func menu(for item: MachineListItem) -> some View {
        if item.offersMakeDefault(defaultID: defaultID) {
            Button { makeDefault(item.id) } label: {
                Label(String(localized: "machines.makeDefault"), systemImage: "star")
            }
        }
        if item.state == .hostKeyChanged {
            Button(action: pair) {
                Label(String(localized: "machines.pairAgain"), systemImage: "qrcode.viewfinder")
            }
        }
        removeButton(for: item, role: .destructive)
    }

    @ViewBuilder private func swipe(for item: MachineListItem) -> some View {
        // No destructive role here: a swipe button with that role slides the row away at once,
        // before the confirmation or the relay has answered.
        removeButton(for: item, role: nil)
            .tint(Color("StatusError"))
        if item.offersMakeDefault(defaultID: defaultID) {
            Button { makeDefault(item.id) } label: {
                Label(String(localized: "machines.makeDefault"), systemImage: "star")
            }
            .tint(Color("AccentText"))
        }
    }

    /// "Remove" for a Mac that already let this iPhone go; "Unpair" (asks first) for the others.
    @ViewBuilder private func removeButton(for item: MachineListItem, role: ButtonRole?) -> some View {
        if item.state == .revoked {
            Button(role: role) { unpairNow(item) } label: {
                Label(String(localized: "machines.remove"), systemImage: "trash")
            }
        } else {
            Button(role: role) { confirming = item } label: {
                Label(String(localized: "machines.unpair"), systemImage: "minus.circle")
            }
        }
    }

    private func unpairNow(_ item: MachineListItem) {
        guard !working.contains(item.id) else { return }
        working.insert(item.id)
        Task {
            do {
                try await unpair(item.id)
            } catch {
                failed = item
            }
            working.remove(item.id)
        }
    }
}

extension MachineList where Header == EmptyView {
    init(
        items: [MachineListItem], defaultID: String?, makeDefault: @escaping (String) -> Void,
        unpair: @escaping (String) async throws -> Void, pair: @escaping () -> Void
    ) {
        self.init(items: items, defaultID: defaultID, makeDefault: makeDefault, unpair: unpair, pair: pair) {
            EmptyView()
        }
    }
}

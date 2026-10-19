import SwiftUI
import ShellXIcons

// Keep the live coordinator above the row subtree. SwiftUI can skip this child
// while its snapshot is unchanged without recursively comparing action closures.
struct SimulatorDevicePickerMenu: View {
    let snapshot: SimulatorDevicePickerSnapshot
    let actions: SimulatorDevicePickerActions

    var body: some View {
        Menu {
            if snapshot.rows.isEmpty {
                SimulatorLocalizedButton(simulatorStrings.refresh, action: actions.refresh)
            } else {
                ForEach(snapshot.rows) { row in
                    Button {
                        actions.select(row.id)
                    } label: {
                        if row.isSelected {
                            ShellXLabel(row.label, icon: "checkmark")
                        } else {
                            Text(row.label)
                        }
                    }
                }
                Divider()
                SimulatorLocalizedButton(simulatorStrings.refresh, action: actions.refresh)
            }
        } label: {
            ShellXLabel(snapshot.selectedDeviceName, icon: snapshot.selectedDeviceSymbol)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

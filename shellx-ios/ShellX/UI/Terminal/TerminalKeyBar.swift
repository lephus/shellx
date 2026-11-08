import ShellXAppCore
import SwiftUI

/// The key bar's buttons: its keys in `TerminalBarKey` order, then hide keyboard.
enum TerminalKeyBarItem: Hashable {
    case key(TerminalBarKey)
    case hideKeyboard
}

/// The keys a phone keyboard lacks, in a row over it: esc, tab, ctrl (held for the next key), the four arrows and, at
/// the trailing end, hide keyboard.
///
/// Each key's touch area is the row's full 44-pt height and its share of the width with the gaps beside it, so it stays
/// at least 44 pt wide on a 375-pt phone, where eight 44-pt caps and their gaps would not fit.
struct TerminalKeyBar: View {
    let ctrlLatched: Bool
    let press: (TerminalKeyBarItem) -> Void

    static let rowHeight: CGFloat = 44
    static let keyHeight: CGFloat = 36
    private static let spacing: CGFloat = 6
    private static let sidePadding: CGFloat = 8
    private static let capMaxWidth: CGFloat = 52

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TerminalBarKey.allCases, id: \.self) { key in
                button(.key(key))
            }
            Spacer(minLength: 0)
            button(.hideKeyboard)
        }
        .padding(.horizontal, Self.sidePadding - Self.spacing / 2)
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
        }
    }

    private func button(_ item: TerminalKeyBarItem) -> some View {
        let latched = item == .key(.ctrl) && ctrlLatched
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button { press(item) } label: {
            cap(item)
                .foregroundStyle(latched ? Color("AccentText") : Color.primary)
                .frame(minWidth: 0, maxWidth: Self.capMaxWidth)
                .frame(height: Self.keyHeight)
                .background(latched ? Color("AccentColor").opacity(0.2) : Color.appBackground, in: shape)
                .overlay {
                    if latched { shape.strokeBorder(Color("AccentColor").opacity(0.45), lineWidth: 1) }
                }
                .padding(.horizontal, Self.spacing / 2)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: Self.capMaxWidth + Self.spacing)
        .accessibilityLabel(Text(Self.label(item)))
        .accessibilityValue(latched ? Text(LocalizedStringResource("terminal.key.ctrl.latched")) : Text(verbatim: ""))
        .accessibilityAddTraits(latched ? .isSelected : [])
        .accessibilityIdentifier(Self.identifier(item))
    }

    @ViewBuilder private func cap(_ item: TerminalKeyBarItem) -> some View {
        switch item {
        case .key(.escape): caption("esc")
        case .key(.tab): caption("tab")
        case .key(.ctrl): caption("ctrl")
        case .key(.left): Image(systemName: "arrow.left")
        case .key(.up): Image(systemName: "arrow.up")
        case .key(.down): Image(systemName: "arrow.down")
        case .key(.right): Image(systemName: "arrow.right")
        case .hideKeyboard: Image(systemName: "keyboard.chevron.compact.down")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private static func label(_ item: TerminalKeyBarItem) -> LocalizedStringResource {
        switch item {
        case .key(.escape): LocalizedStringResource("terminal.key.escape")
        case .key(.tab): LocalizedStringResource("terminal.key.tab")
        case .key(.ctrl): LocalizedStringResource("terminal.key.ctrl")
        case .key(.left): LocalizedStringResource("terminal.key.left")
        case .key(.up): LocalizedStringResource("terminal.key.up")
        case .key(.down): LocalizedStringResource("terminal.key.down")
        case .key(.right): LocalizedStringResource("terminal.key.right")
        case .hideKeyboard: LocalizedStringResource("terminal.key.hideKeyboard")
        }
    }

    private static func identifier(_ item: TerminalKeyBarItem) -> String {
        switch item {
        case .key(.escape): "terminal.key.escape"
        case .key(.tab): "terminal.key.tab"
        case .key(.ctrl): "terminal.key.ctrl"
        case .key(.left): "terminal.key.left"
        case .key(.up): "terminal.key.up"
        case .key(.down): "terminal.key.down"
        case .key(.right): "terminal.key.right"
        case .hideKeyboard: "terminal.key.hideKeyboard"
        }
    }
}

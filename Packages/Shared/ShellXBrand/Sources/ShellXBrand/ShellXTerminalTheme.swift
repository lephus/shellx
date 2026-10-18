/// ShellX's built-in terminal theme (spec §7.4, "Bảng màu terminal mặc
/// định"): background `bg`, cursor `primary`, text `text`, and 16 ANSI
/// colors tuned to the palette.
///
/// It is only the managed default. The app applies it when the user's
/// Ghostty config sets no `theme` and no terminal colors; any authored
/// theme or color always wins.
///
/// | #  | name           | hex       | source                          |
/// |----|----------------|-----------|---------------------------------|
/// | 0  | black          | `#211a37` | `line`                          |
/// | 1  | red            | `#e88a8a` | `error`                         |
/// | 2  | green          | `#6fd49a` | `done`                          |
/// | 3  | yellow         | `#e8c468` | `running`                       |
/// | 4  | blue           | `#60a5fa` | `primary`                       |
/// | 5  | magenta        | `#c49af0` | soft violet, tuned              |
/// | 6  | cyan           | `#6fc8d9` | soft cyan, tuned                |
/// | 7  | white          | `#cdc7e0` | `text`                          |
/// | 8  | bright black   | `#6e6790` | between `border` and `muted`    |
/// | 9  | bright red     | `#f2a7a7` | `error`, lighter                |
/// | 10 | bright green   | `#93e2b4` | `done`, lighter                 |
/// | 11 | bright yellow  | `#f2d68f` | `running`, lighter              |
/// | 12 | bright blue    | `#93c5fd` | `primary-text`                  |
/// | 13 | bright magenta | `#d9b8f7` | magenta, lighter                |
/// | 14 | bright cyan    | `#96dbe7` | cyan, lighter                   |
/// | 15 | bright white   | `#e6e2f2` | `text-hi`                       |
///
/// Selection is `#233356` (`primary` at 28% over `bg`) with `text-hi` on
/// it; the cursor draws `bg` text over `primary`. Every colored entry
/// reads at 4.5:1 or better on `bg`, bright black at 3.7:1.
public enum ShellXTerminalTheme {
    /// Theme name, also the managed default theme name the terminal core
    /// looks up before falling back to ``ghosttyConfigContents``.
    public static let name = "ShellX"

    public static let background = ShellXPalette.bg
    public static let foreground = ShellXPalette.text
    public static let cursor = ShellXPalette.primary
    public static let cursorText = ShellXPalette.bg
    public static let selectionBackground = ShellXColor(hex: 0x233356)
    public static let selectionForeground = ShellXPalette.textHi

    /// ANSI colors 0-15, in palette index order.
    public static let ansi: [ShellXColor] = [
        ShellXPalette.line,
        ShellXPalette.error,
        ShellXPalette.done,
        ShellXPalette.running,
        ShellXPalette.primary,
        ShellXColor(hex: 0xc49af0),
        ShellXColor(hex: 0x6fc8d9),
        ShellXPalette.text,
        ShellXColor(hex: 0x6e6790),
        ShellXColor(hex: 0xf2a7a7),
        ShellXColor(hex: 0x93e2b4),
        ShellXColor(hex: 0xf2d68f),
        ShellXPalette.primaryText,
        ShellXColor(hex: 0xd9b8f7),
        ShellXColor(hex: 0x96dbe7),
        ShellXPalette.textHi,
    ]

    /// The theme as Ghostty config lines (the same format as a Ghostty
    /// theme file).
    public static var ghosttyConfigContents: String {
        var lines = ansi.enumerated().map { index, color in
            "palette = \(index)=\(color.hexString)"
        }
        lines.append("background = \(background.hexString)")
        lines.append("foreground = \(foreground.hexString)")
        lines.append("cursor-color = \(cursor.hexString)")
        lines.append("cursor-text = \(cursorText.hexString)")
        lines.append("selection-background = \(selectionBackground.hexString)")
        lines.append("selection-foreground = \(selectionForeground.hexString)")
        return lines.joined(separator: "\n")
    }
}

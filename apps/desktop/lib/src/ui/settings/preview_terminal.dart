import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../../config/config_theme.dart';
import '../../config/shellx_config.dart';
import '../../config/theme_listing.dart';
import '../../terminal/terminal_appearance.dart' show terminalCursorFor;
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../theme/shellx_desktop_theme.dart';
import 'settings_preview.dart';

/// Columns and rows of the sample (a fixed grid, A11 D8).
const int kPreviewCols = 56, kPreviewRows = 10;

/// The sample's text: a prompt, `ls --color`, a diff, an error, the sixteen
/// base colours in two rows, Vietnamese, CJK and an emoji, and the cursor on
/// a fresh prompt. Fixed: it shows the theme and the font, not the user's
/// files.
const String kPreviewSample =
    '\x1b[32mme@mac\x1b[0m \x1b[34m~/work\x1b[0m \$ ls --color\r\n'
    '\x1b[34mlib\x1b[0m  \x1b[34mtest\x1b[0m  pubspec.yaml  \x1b[32mrun.sh\x1b[0m\r\n'
    '\x1b[31m-old line\x1b[0m\r\n'
    '\x1b[32m+new line\x1b[0m\r\n'
    '\x1b[1;31merror:\x1b[0m \x1b[31mcommand not found\x1b[0m\r\n'
    '\x1b[40m  \x1b[41m  \x1b[42m  \x1b[43m  \x1b[44m  \x1b[45m  \x1b[46m  \x1b[47m  \x1b[0m\r\n'
    '\x1b[100m  \x1b[101m  \x1b[102m  \x1b[103m  \x1b[104m  \x1b[105m  \x1b[106m  \x1b[107m  \x1b[0m\r\n'
    'Tiếng Việt 日本語 🙂\r\n'
    '\x1b[32mme@mac\x1b[0m \x1b[34m~/work\x1b[0m \$ ';

/// The themes on this computer, ShellX's own first (read once per opening of
/// Settings).
final themeListProvider = FutureProvider.autoDispose<List<ThemeEntry>>(
  (ref) =>
      listThemes(ref.read(configPathsProvider), ref.read(configFsProvider)),
);

/// A theme as the real panes would draw it (the file under the colours the
/// configuration sets itself), [failed] when its file couldn't be used.
typedef PreviewTheme = ({ResolvedTheme theme, bool failed});

final previewThemeProvider = FutureProvider.autoDispose
    .family<PreviewTheme, String>((ref, name) async {
      final config = ref.read(shellxConfigProvider).config;
      final problems = <ConfigProblem>[];
      final resolved = await resolveTheme(
        ShellxConfig(
          theme: name,
          background: config.background,
          foreground: config.foreground,
          cursorColor: config.cursorColor,
          selectionBackground: config.selectionBackground,
          palette: config.palette,
        ),
        ref.read(configPathsProvider),
        fs: ref.read(configFsProvider),
        problems: problems,
      );
      return (
        theme: resolved.theme,
        failed: problems.any((p) => p.code == ConfigProblemCode.themeNotFound),
      );
    });

/// A read-only terminal with the sample, drawn with the app's own
/// `TerminalStyle` and `TerminalTheme`. It follows the saved configuration
/// and, while the user hovers, focuses or drags, the values of
/// [settingsPreviewProvider]. It owns no keyboard and no pointer.
class PreviewTerminal extends ConsumerStatefulWidget {
  const PreviewTerminal({super.key});

  @override
  ConsumerState<PreviewTerminal> createState() => _PreviewTerminalState();
}

class _PreviewTerminalState extends ConsumerState<PreviewTerminal> {
  late final Terminal _terminal = Terminal(maxLines: 50)
    ..resize(kPreviewCols, kPreviewRows)
    ..write(kPreviewSample);

  /// The last preview theme that was ready: kept while the next one loads.
  ResolvedTheme? _lastPreviewTheme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    final config = state.config;
    final preview = ref.watch(settingsPreviewProvider);
    final liveSize = ref.watch(terminalFontSizeProvider);

    var theme = state.theme;
    final previewName = preview?.theme;
    if (previewName != null) {
      final resolved = ref.watch(previewThemeProvider(previewName));
      final ready = resolved.value;
      if (ready != null) _lastPreviewTheme = ready.theme;
      theme = ready?.theme ?? _lastPreviewTheme ?? theme;
    }
    final style = desktopTerminalStyle(
      preview?.fontSize ?? liveSize,
      families: preview?.families ?? config.fontFamilies,
      regular:
          (preview?.weight ?? config.fontWeight) == TerminalFontWeight.regular,
      cellHeightPercent: preview?.cellHeightPercent ?? config.cellHeightPercent,
    );
    const pad = 8.0;
    final cell = measureTerminalCell(style, TextScaler.noScaling);
    final natural = Size(
      kPreviewCols * cell.width + 2 * pad,
      kPreviewRows * cell.height + 2 * pad,
    );
    return Semantics(
      container: true,
      label: l10n.settingsPreviewLabel,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          border: Border.all(color: ShellxDesktopColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: ExcludeFocus(
              child: IgnorePointer(
                child: SizedBox(
                  width: natural.width,
                  height: natural.height,
                  child: TerminalView(
                    _terminal,
                    theme: theme.terminal,
                    textStyle: style,
                    textScaler: TextScaler.noScaling,
                    padding: const EdgeInsets.all(pad),
                    autoResize: false,
                    autofocus: false,
                    readOnly: true,
                    hardwareKeyboardOnly: true,
                    alwaysShowCursor: true,
                    cursorType: terminalCursorFor(config.cursorShape),
                    simulateScroll: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui' show Color;

import 'config_controller.dart';
import 'shellx_config.dart';

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _pair(double a, double b) => a == b ? _n(a) : '${_n(a)},${_n(b)}';

/// `shellx config show` (D39): every key in effect and the line it comes
/// from (`default` when no line sets it). Values only, never file text.
List<Map<String, String>> configShowValues(ConfigState s) {
  final c = s.config;
  String source(String key) {
    final o = c.origins[key];
    return o == null ? 'default' : '${o.file}:${o.line}';
  }

  Map<String, String> v(String key, String value) => {
    'key': key,
    'value': value,
    'source': source(key),
  };
  String at(entry) => '${entry.file}:${entry.line}';

  return [
    v(
      'font-family',
      c.fontFamilies.isEmpty ? 'JetBrains Mono' : c.fontFamilies.join(', '),
    ),
    v(
      'font-size',
      c.fontSize == null
          ? '13 (or the size set with Cmd/Ctrl +/-)'
          : _n(c.fontSize!),
    ),
    v('font-thicken', '${c.fontThicken}'),
    v('theme', s.theme.name ?? 'ShellX'),
    v('background', _hex(s.theme.background)),
    v('foreground', _hex(s.theme.terminal.foreground)),
    v('cursor-color', c.cursorColor == null ? 'theme' : _hex(c.cursorColor!)),
    v(
      'selection-background',
      c.selectionBackground == null ? 'theme' : _hex(c.selectionBackground!),
    ),
    v(
      'palette',
      c.palette.isEmpty
          ? 'theme'
          : (c.palette.entries.toList()..sort((a, b) => a.key - b.key))
                .map((e) => '${e.key}=${_hex(e.value)}')
                .join(', '),
    ),
    v('cursor-style', c.cursorShape.name),
    v('scrollback-limit', '${c.scrollbackLimit}'),
    v('window-padding-x', _pair(c.padding.left, c.padding.right)),
    v('window-padding-y', _pair(c.padding.top, c.padding.bottom)),
    v('macos-option-as-alt', switch (c.optionAsAlt) {
      OptionAsAlt.off => 'false',
      OptionAsAlt.both => 'true',
      OptionAsAlt.left => 'left',
      OptionAsAlt.right => 'right',
    }),
    v('confirm-close-surface', switch (c.confirmClose) {
      ConfirmClose.whenRunning => 'true',
      ConfirmClose.never => 'false',
      ConfirmClose.always => 'always',
    }),
    v('working-directory', switch (c.workingDirectory.kind) {
      WorkingDirectoryKind.home => 'home',
      WorkingDirectoryKind.inherit => 'inherit',
      WorkingDirectoryKind.path => c.workingDirectory.path!,
    }),
    v('ghostty-config', '${c.ghosttyConfig}'),
    for (final k in c.keybinds)
      {'key': 'keybind', 'value': k.value, 'source': at(k.origin)},
    for (final u in c.commands)
      {
        'key': u.enter ? 'command' : 'snippet',
        'value': '${u.name} = ${u.text.replaceAll('\n', r'\n')}',
        'source': at(u.origin),
      },
  ];
}

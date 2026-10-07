import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../config/config_controller.dart';
import '../config/shellx_config.dart';

/// What every pane draws with (A9 D11, D15, D16, D18). Without a
/// configuration: A1's palette, block cursor, 10 / 6 padding, JetBrains
/// Mono.
@immutable
final class TerminalAppearance {
  const TerminalAppearance({
    required this.theme,
    required this.background,
    required this.focusOutline,
    required this.cursor,
    required this.padding,
    required this.families,
    this.regular = false,
  });

  final TerminalTheme theme;

  /// The terminal area behind and around panes (D15).
  final Color background;

  /// A3 D16's pane outline, readable on [background] (D15).
  final Color focusOutline;
  final TerminalCursorType cursor;
  final EdgeInsets padding;

  /// Primary family first, then fallbacks (D11); empty = JetBrains Mono.
  final List<String> families;

  /// `font-weight = regular`: the bundled font's Regular face, not Light.
  final bool regular;
}

TerminalCursorType terminalCursorFor(CursorShape shape) => switch (shape) {
  CursorShape.block => TerminalCursorType.block,
  CursorShape.bar => TerminalCursorType.verticalBar,
  CursorShape.underline => TerminalCursorType.underline,
};

final terminalAppearanceProvider = Provider<TerminalAppearance>((ref) {
  // A runtime report or a notice ack keeps both: no rebuild of the panes.
  final (config, theme) = ref.watch(
    shellxConfigProvider.select((s) => (s.config, s.theme)),
  );
  return TerminalAppearance(
    theme: theme.terminal,
    background: theme.background,
    focusOutline: theme.focusOutline,
    cursor: terminalCursorFor(config.cursorShape),
    padding: config.padding,
    families: config.fontFamilies,
    regular: config.fontWeight == TerminalFontWeight.regular,
  );
});

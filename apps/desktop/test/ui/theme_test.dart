import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:shellx_desktop/src/ui/theme/terminal_colors.dart';

void main() {
  test('one dark theme built from the UI §1 tokens', () {
    final theme = buildDesktopTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, ShellxDesktopColors.bgTerminal);
    expect(theme.colorScheme.primary, ShellxDesktopColors.primary);
    expect(theme.colorScheme.surface, ShellxDesktopColors.surface);
    expect(theme.colorScheme.error, ShellxDesktopColors.errDialog);
  });

  test('the UI font is the platform default (no fontFamily, UI §1.3)', () {
    final theme = buildDesktopTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('JetBrainsMono'));
    expect(ShellxText.body.fontFamily, isNull);
    expect(ShellxText.body.fontSize, 13);
    expect(ShellxText.body.height! * 13, closeTo(18, 0.01));
  });

  test('tokens match UI §1.1 and the mobile terminal palette', () {
    expect(ShellxDesktopColors.bgTerminal, const Color(0xFF0B1215));
    expect(ShellxDesktopColors.bgSidebar, const Color(0xFF111B1E));
    expect(ShellxDesktopColors.accent, const Color(0xFF5FD4E2));
    expect(ShellxDesktopColors.warnBg, const Color(0xFF2A2412));
    expect(ShellxDesktopColors.scrim, const Color(0x99000000));
    expect(TerminalColors.theme.background, ShellxDesktopColors.bgTerminal);
    expect(TerminalColors.theme.selection, const Color(0x665FD4E2));
    expect(ShellxSizes.sidebarWidth, 220);
    expect(ShellxSizes.minWindow, const Size(640, 400));
    expect(ShellxSizes.defaultWindow, const Size(1100, 720));
  });
}

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

  test('row fills step up: hover < selected < pressed (S-7)', () {
    double l(Color c) => c.computeLuminance();
    expect(
      l(ShellxDesktopColors.rowHover),
      lessThan(l(ShellxDesktopColors.rowSelected)),
    );
    expect(
      l(ShellxDesktopColors.rowSelected),
      lessThan(l(ShellxDesktopColors.rowPressed)),
    );
    final sidebar = l(ShellxDesktopColors.bgSidebar);
    final ratio =
        (l(ShellxDesktopColors.rowSelected) + 0.05) / (sidebar + 0.05);
    expect(ratio, greaterThan(1.25));
  });

  test('styles that replace the ambient one carry the platform UI font '
      '(P-4)', () {
    final theme = buildDesktopTheme();
    final family = theme.textTheme.bodyMedium!.fontFamily;
    expect(family, isNotNull);
    expect(theme.tooltipTheme.textStyle!.fontFamily, family);
    final dialog = buildDialogTheme(theme, reduceMotion: false);
    for (final style in [
      dialog.textTheme.titleLarge,
      dialog.textTheme.headlineSmall,
      dialog.textTheme.bodyLarge,
      dialog.textTheme.bodyMedium,
      dialog.textTheme.bodySmall,
      dialog.textTheme.labelLarge,
      dialog.filledButtonTheme.style!.textStyle!.resolve({}),
      dialog.outlinedButtonTheme.style!.textStyle!.resolve({}),
    ]) {
      expect(style!.fontFamily, family);
      expect(style.fontFamily, isNot('JetBrainsMono'));
    }
    expect(dialog.textTheme.titleLarge!.fontSize, 17);
  });

  test('filled dialog buttons ring outside the fill on keyboard focus; '
      'outlined ones keep the inside ring (S-9)', () {
    final dialog = buildDialogTheme(buildDesktopTheme(), reduceMotion: false);
    final filled = dialog.filledButtonTheme.style!;
    expect(
      filled.shape!.resolve({WidgetState.focused}),
      isA<OutsideFocusRingBorder>(),
    );
    expect(filled.shape!.resolve({}), isNot(isA<OutsideFocusRingBorder>()));
    expect(filled.side!.resolve({WidgetState.focused}), isNull);
    final outlined = dialog.outlinedButtonTheme.style!;
    expect(
      outlined.side!.resolve({WidgetState.focused})!.color,
      ShellxDesktopColors.accent,
    );
  });

  test('text fields are 36 high with the label above (UI §3.4)', () {
    final input = buildDesktopTheme().inputDecorationTheme;
    expect(input.isDense, isTrue);
    expect(
      input.contentPadding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  });
}

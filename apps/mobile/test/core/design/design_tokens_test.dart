import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/shared/shared.dart';

import '../../support/app_harness.dart';

/// Values copied from `docs/superpowers/design/2026-09-25-shellx-mobile-ui.html`.
void main() {
  test('light palette = the design\'s light --a-* tokens', () {
    final c = Brightness.light.appColors;
    expect(c.background, const Color(0xFFF2F7F8));
    expect(c.surface, const Color(0xFFFFFFFF));
    expect(c.primaryText, const Color(0xFF111111));
    expect(c.secondaryText, const Color(0xFF434B56));
    expect(c.disable, const Color(0xFF8B8F95));
    expect(c.border, const Color(0xFFD8D9DB));
    expect(c.divider, const Color(0xFFEBECED));
    expect(c.primary, const Color(0xFF0097A8));
    expect(c.onPrimary, const Color(0xFFFFFFFF));
    expect(c.primarySoft, const Color(0xFFDCF1F3));
    expect(c.ok, const Color(0xFF3E8A2B));
    expect(c.okDot, const Color(0xFF4CAF3A));
    expect(c.warn, const Color(0xFF9A5600));
    expect(c.warnSoft, const Color(0xFFFCF2E5));
    expect(c.error, const Color(0xFFCB232B));
    expect(c.errorSoft, const Color(0xFFFAE9EA));
    expect(c.keyboardBackground, const Color(0xFFD1D4DA));
  });

  test('dark palette = the design\'s dark --a-* tokens (not the base placeholder)', () {
    final c = Brightness.dark.appColors;
    expect(c.background, const Color(0xFF0D1315));
    expect(c.surface, const Color(0xFF172023));
    expect(c.primaryText, const Color(0xFFE8EFF1));
    expect(c.secondaryText, const Color(0xFFA7B6BA));
    expect(c.disable, const Color(0xFF6F8186));
    expect(c.border, const Color(0xFF2B373A));
    expect(c.divider, const Color(0xFF1F292C));
    expect(c.primary, const Color(0xFF2DBFCF));
    expect(c.onPrimary, const Color(0xFF04282D));
    expect(c.primarySoft, const Color(0xFF0E363C));
    expect(c.okDot, const Color(0xFF6BCB4E));
    expect(c.warn, const Color(0xFFF0A94A));
    expect(c.error, const Color(0xFFF26A70));
    expect(c.errorSoft, const Color(0xFF3B1719));
    expect(c.keyboardKey, const Color(0xFF47484B));
  });

  test('the terminal is dark in both themes (--t-*)', () {
    expect(TerminalColors.theme.background, const Color(0xFF0B1215));
    expect(TerminalColors.theme.foreground, const Color(0xFFD4E1E4));
    expect(TerminalColors.theme.green, const Color(0xFF7ED492));
    expect(TerminalColors.theme.cyan, const Color(0xFF5FD4E2));
    expect(TerminalColors.chrome, const Color(0xFF111B1E));
  });

  test('UI text uses lining numerals; Material widgets take the ShellX primary', () {
    expect(AppTypography.instance.paragraph.fontFeatures, AppTypography.liningFigures);
    expect(AppTypography.instance.display32.fontFeatures, AppTypography.liningFigures);
    final theme = ThemeDataFactory.create(Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFF2DBFCF));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0D1315));
  });

  testWidgets('buttons: 54 pt, radius 15; disabled keeps its colours at 45 % opacity', (tester) async {
    await tester.pumpWidget(
      localized(
        const Scaffold(
          body: Column(
            children: [
              AppButton(title: 'on'),
              AppButton(title: 'off', state: ButtonState.disable),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.widgetWithText(AppButton, 'on')).height, 54);
    final ink = tester.widget<Ink>(
      find.descendant(of: find.widgetWithText(AppButton, 'on'), matching: find.byType(Ink)),
    );
    expect((ink.decoration! as BoxDecoration).borderRadius, BorderRadius.circular(15));
    final dimmed = tester.widget<Opacity>(
      find.descendant(of: find.widgetWithText(AppButton, 'off'), matching: find.byType(Opacity)).first,
    );
    expect(dimmed.opacity, 0.45);
  });
}

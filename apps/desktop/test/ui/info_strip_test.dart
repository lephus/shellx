import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/ui/terminal/info_strip.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

const _text = 'ShellX đã đóng bất thường lần trước. Đã mở lại 5 tab.';

Future<void> pumpStrip(
  WidgetTester t, {
  required VoidCallback onClose,
  FocusNode? focusNode,
  double textScale = 1,
  double width = 1400,
  String text = _text,
}) async {
  t.view.physicalSize = Size(width, 400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoStrip(
                icon: Icons.history,
                iconColor: ShellxDesktopColors.textSecondary,
                text: text,
                closeText: 'Đóng',
                closeLabel: 'Đóng thông báo khôi phục',
                focusNode: focusNode,
                onClose: onClose,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('36 px, rowSelected, live region, close button works', (t) async {
    var closed = 0;
    await pumpStrip(t, onClose: () => closed++);
    expect(t.getSize(find.byType(InfoStrip)).height, 36);
    final box =
        t.widget<Container>(find.byKey(const Key('infoStrip'))).decoration!
            as BoxDecoration;
    expect(box.color, ShellxDesktopColors.rowSelected);
    expect(find.text('Đóng'), findsOneWidget);
    expect(find.bySemanticsLabel('Đóng thông báo khôi phục'), findsOneWidget);
    await t.tap(find.byKey(const Key('infoStrip.close')));
    expect(closed, 1);
    final semantics = t.getSemantics(find.byKey(const Key('infoStrip')));
    expect(semantics.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets('the focus node is the close button; Esc closes from inside', (
    t,
  ) async {
    var closed = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpStrip(t, onClose: () => closed++, focusNode: focus);
    focus.requestFocus();
    await t.pump();
    final button = t.widget<TextButton>(
      find.byKey(const Key('infoStrip.close')),
    );
    expect(button.focusNode, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, 1);
  });

  testWidgets('large text: the strip grows to max(36, 18·s + 18) (UI-A5 §4)', (
    t,
  ) async {
    await pumpStrip(t, onClose: () {}, textScale: 2);
    expect(t.getSize(find.byType(InfoStrip)).height, 54);
  });

  testWidgets('a cut text gets a tooltip with the full text; a whole one '
      'none', (t) async {
    await pumpStrip(t, onClose: () {});
    expect(find.byType(Tooltip), findsNothing);
    await pumpStrip(t, onClose: () {}, width: 300);
    final tooltip = t.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, _text);
    expect(tooltip.excludeFromSemantics, isTrue);
  });
}

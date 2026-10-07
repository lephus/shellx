import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/terminal/find_session.dart';
import 'package:shellx_desktop/src/ui/terminal/find_bar.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';
import 'package:xterm/xterm.dart';

const _dim = Color(0x405FD4E2);
const _hot = Color(0x8C5FD4E2);

class Rig {
  Rig(String text, {Locale locale = const Locale('en')}) : _locale = locale {
    terminal = Terminal(maxLines: 500)..resize(30, 5);
    terminal.write(text);
    controller = TerminalController();
    session = FindSession(
      terminal: terminal,
      controller: controller,
      matchColor: _dim,
      currentColor: _hot,
    );
  }
  final Locale _locale;
  late final Terminal terminal;
  late final TerminalController controller;
  late final FindSession session;
  final focus = FocusNode();
  var closed = 0;

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(focus.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: FindBar(
              session: session,
              focusNode: focus,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }
}

void main() {
  testWidgets('opens focused; typing counts matches "3 of 3"', (t) async {
    final r = Rig('one error\r\ntwo error\r\nthree error');
    await r.pump(t);
    expect(r.focus.hasFocus, isTrue);
    await t.enterText(find.byKey(const Key('find.field')), 'error');
    await t.pump();
    expect(t.widget<Text>(find.byKey(const Key('find.count'))).data, '3 of 3');
    r.session.close();
  });

  testWidgets('Vietnamese words, and no matches shown in red', (t) async {
    final r = Rig('x', locale: const Locale('vi'));
    await r.pump(t);
    await t.enterText(find.byKey(const Key('find.field')), 'zzz');
    await t.pump();
    final count = t.widget<Text>(find.byKey(const Key('find.count')));
    expect(count.data, 'Không có kết quả');
    expect(count.style!.color, ShellxDesktopColors.err);
    r.session.close();
  });

  testWidgets('Enter is next, Shift+Enter previous, Esc closes', (t) async {
    final r = Rig('a\r\na\r\na');
    await r.pump(t);
    await t.enterText(find.byKey(const Key('find.field')), 'a');
    await t.pump();
    expect(r.session.current, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(r.session.current, 0);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(r.session.current, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(r.session.current, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(r.closed, 1);
    r.session.close();
  });

  testWidgets('a selected line seeds the field', (t) async {
    final r = Rig('find me here');
    r.session.setQuery('me here'); // what FindSessions.open does
    await r.pump(t);
    expect(
      t.widget<TextField>(find.byKey(const Key('find.field'))).controller!.text,
      'me here',
    );
    expect(r.session.matches, hasLength(1));
    r.session.close();
  });

  testWidgets('previous/next are disabled without matches; Aa toggles', (
    t,
  ) async {
    final r = Rig('Err err');
    await r.pump(t);
    IconButton button(String key) => t.widget<IconButton>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(IconButton),
      ),
    );
    expect(button('find.next').onPressed, isNull);
    await t.enterText(find.byKey(const Key('find.field')), 'err');
    await t.pump();
    expect(button('find.next').onPressed, isNotNull);
    expect(r.session.matches, hasLength(2));
    await t.tap(find.byKey(const Key('find.matchCase')));
    await t.pump();
    expect(r.session.matches, hasLength(1));
    await t.tap(find.byKey(const Key('find.close')));
    expect(r.closed, 1);
    r.session.close();
  });

  testWidgets('360 × 36', (t) async {
    final r = Rig('x');
    await r.pump(t);
    expect(t.getSize(find.byKey(const Key('find.bar'))), const Size(360, 36));
    r.session.close();
  });

  testWidgets('Esc and Enter belong to the input method while it composes', (
    t,
  ) async {
    final r = Rig('a\r\na');
    await r.pump(t);
    await t.showKeyboard(find.byKey(const Key('find.field')));
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(r.closed, 0, reason: 'Esc cancels the composition, not the bar');
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(r.closed, 1);
    r.session.close();
  });
}

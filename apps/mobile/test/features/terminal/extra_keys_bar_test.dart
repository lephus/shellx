import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_mobile/core/core.dart' hide test;
import 'package:shellx_mobile/features/terminal/domain/shellx_terminal.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/extra_keys_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';

import '../../support/app_harness.dart';

void main() {
  late DateTime now;
  late ExtraKeysController keys;
  late ShellxTerminal terminal;
  late List<String> out;
  late int pastes;

  Widget bar() => localized(
    Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ExtraKeysBar(
          controller: keys,
          onKey: (key) => keys.sendKey(key, terminal),
          onPaste: () => pastes++,
        ),
      ),
    ),
  );

  Finder keyCap(ExtraKey key) => find.byKey(ValueKey('extra-key-${key.name}'));

  setUp(() {
    now = DateTime(2026, 9, 25);
    keys = ExtraKeysController(now: () => now);
    out = [];
    terminal = ShellxTerminal(modifiers: keys)..onOutput = out.add;
    pastes = 0;
  });

  tearDown(() => keys.dispose());

  testWidgets('shows every key of spec §9.3 with the localised Paste label', (tester) async {
    await tester.pumpWidget(bar());
    expect(find.text('Esc'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dán').hitTestable(),
      100,
      scrollable: find.descendant(of: find.byType(ExtraKeysBar), matching: find.byType(Scrollable)),
    );
    expect(find.text('PgDn'), findsOneWidget);
    await tester.tap(find.text('Dán'));
    expect(pastes, 1);
  });

  BoxDecoration capDecoration(WidgetTester tester, ExtraKey key) {
    final cap = find.descendant(
      of: keyCap(key),
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.decoration is BoxDecoration && widget.constraints?.minWidth == 46,
      ),
    );
    return tester.widget<Container>(cap).decoration! as BoxDecoration;
  }

  testWidgets('design: Ctrl once = primary outline on a plain key, locked = filled with a dot', (tester) async {
    final colors = Brightness.light.appColors;
    await tester.pumpWidget(bar());
    expect(capDecoration(tester, ExtraKey.ctrl).border, isNull);

    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    final once = capDecoration(tester, ExtraKey.ctrl);
    expect(once.color, colors.keyboardKey);
    expect((once.border! as Border).top.color, colors.primary);
    expect(find.byKey(const ValueKey('latch-locked')), findsNothing);

    now = now.add(const Duration(milliseconds: 150));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    final locked = capDecoration(tester, ExtraKey.ctrl);
    expect(locked.color, colors.primary);
    expect(locked.border, isNull);
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-locked'))),
      findsOneWidget,
    );
  });

  testWidgets('keys are 50 pt touch targets on the keyboard colour', (tester) async {
    await tester.pumpWidget(bar());
    expect(tester.getSize(keyCap(ExtraKey.esc)).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byType(ExtraKeysBar)).height, ExtraKeysBar.height);
  });

  testWidgets('tap Ctrl then type c on the soft keyboard sends ^C', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-one-shot'))),
      findsOneWidget,
    );

    terminal.textInput('c');
    await tester.pump();
    expect(out, ['\x03']);
    expect(find.byKey(const ValueKey('latch-one-shot')), findsNothing);
  });

  testWidgets('double tap locks Ctrl, a third tap unlocks', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.ctrl));
    now = now.add(const Duration(milliseconds: 150));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(
      find.descendant(of: keyCap(ExtraKey.ctrl), matching: find.byKey(const ValueKey('latch-locked'))),
      findsOneWidget,
    );

    terminal.textInput('c');
    terminal.textInput('d');
    expect(out, ['\x03', '\x04']);

    now = now.add(const Duration(seconds: 2));
    await tester.tap(keyCap(ExtraKey.ctrl));
    await tester.pump();
    expect(find.byKey(const ValueKey('latch-locked')), findsNothing);
  });

  testWidgets('arrow key cap sends through xterm', (tester) async {
    await tester.pumpWidget(bar());
    await tester.tap(keyCap(ExtraKey.up));
    expect(out, ['\x1b[A']);
  });
}

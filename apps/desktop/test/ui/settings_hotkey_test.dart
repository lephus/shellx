import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/platform/global_hotkey.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../platform/global_hotkey_test.dart' show FakeGlobalHotkey;
import '../support/config_harness.dart';
import '../support/config_workspace.dart';
import '../support/memory_config_fs.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const ctrl = LogicalKeyboardKey.controlLeft;
const alt = LogicalKeyboardKey.altLeft;

Future<void> chord(
  WidgetTester t,
  List<LogicalKeyboardKey> held,
  LogicalKeyboardKey key,
) async {
  for (final k in held) {
    await t.sendKeyDownEvent(k);
  }
  await t.sendKeyEvent(key);
  for (final k in held.reversed) {
    await t.sendKeyUpEvent(k);
  }
  await t.pumpAndSettle();
}

typedef W = ({dynamic container, MemoryConfigFs fs, FakeGlobalHotkey hotkey});

Future<W> openTerminalPage(
  WidgetTester t, {
  String config = '',
  bool accept = true,
}) async {
  final hotkey = FakeGlobalHotkey()..accept = accept;
  final w = await pumpConfiguredWorkspace(
    t,
    config: config,
    extra: [globalHotkeyProvider.overrideWithValue(hotkey)],
  );
  w.container.read(globalHotkeyBinderProvider);
  await t.pumpAndSettle();
  await chord(t, [cmd], LogicalKeyboardKey.comma);
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.terminal')));
  await t.pumpAndSettle();
  final list = find
      .descendant(
        of: find.byType(SettingsOverlay),
        matching: find.byType(ListView),
      )
      .last;
  for (var n = 0; n < 12; n++) {
    if (find.byKey(const Key('setting.global-hotkey')).evaluate().isNotEmpty) {
      break;
    }
    await t.drag(list, const Offset(0, -200));
    await t.pump();
  }
  await t.ensureVisible(find.byKey(const Key('setting.global-hotkey')));
  await t.pumpAndSettle();
  return (container: w.container, fs: w.fs, hotkey: hotkey);
}

/// The ShellX file as written; '' while nothing has written it yet.
String fileText(W w) {
  try {
    return w.fs.text(testConfigPaths().shellx);
  } on TypeError {
    return '';
  }
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('the row says "Not set" and opening the page writes nothing', (
    t,
  ) async {
    final w = await openTerminalPage(t);
    expect(find.text('Show or hide ShellX from anywhere'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('setting.global-hotkey')),
        matching: find.text('Not set'),
      ),
      findsOneWidget,
    );
    expect(fileText(w), isNot(contains('global-hotkey =')));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('recording a chord writes the key and registers it', (t) async {
    final w = await openTerminalPage(t);
    await t.tap(find.byKey(const Key('setting.global-hotkey.record')));
    await t.pumpAndSettle();
    expect(find.text('Press the keys…'), findsOneWidget);
    await chord(t, [ctrl, alt], LogicalKeyboardKey.keyJ);
    expect(fileText(w), contains('global-hotkey = ctrl+alt+j'));
    expect(
      find.descendant(
        of: find.byKey(const Key('setting.global-hotkey')),
        matching: find.text('⌃⌥J'),
      ),
      findsOneWidget,
    );
    expect(w.hotkey.chord, isNotNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a key without a modifier is refused with the loader\'s words '
      'and nothing is written', (t) async {
    final w = await openTerminalPage(t);
    await t.tap(find.byKey(const Key('setting.global-hotkey.record')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await t.pumpAndSettle();
    expect(
      find.byKey(const Key('setting.global-hotkey.error')),
      findsOneWidget,
    );
    expect(fileText(w), isNot(contains('global-hotkey =')));
    expect(w.hotkey.chord, isNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Esc cancels the recording, writes nothing, keeps the window '
      'open and gives the keyboard back to the button', (t) async {
    final w = await openTerminalPage(t);
    await t.tap(find.byKey(const Key('setting.global-hotkey.record')));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsOneWidget);
    expect(find.text('Press the keys…'), findsNothing);
    expect(fileText(w), isNot(contains('global-hotkey =')));
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<OutlinedButton>(),
      isNotNull,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a modifier alone is shown while held and never recorded', (
    t,
  ) async {
    final w = await openTerminalPage(t);
    await t.tap(find.byKey(const Key('setting.global-hotkey.record')));
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(ctrl);
    await t.pump();
    expect(find.text('⌃…'), findsOneWidget);
    await t.sendKeyUpEvent(ctrl);
    await t.pumpAndSettle();
    expect(fileText(w), isNot(contains('global-hotkey =')));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Reset takes the key out of effect without deleting the line', (
    t,
  ) async {
    final w = await openTerminalPage(t, config: 'global-hotkey = ctrl+alt+j\n');
    expect(w.hotkey.chord, isNotNull);
    await t.tap(find.byKey(const Key('setting.global-hotkey.reset')));
    await t.pumpAndSettle();
    expect(w.hotkey.chord, isNull);
    expect(fileText(w), contains('global-hotkey'));
    expect(
      fileText(w),
      isNot(matches(RegExp(r'^global-hotkey = ctrl', multiLine: true))),
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a shortcut another app holds is said under the row', (t) async {
    final w = await openTerminalPage(
      t,
      config: 'global-hotkey = ctrl+alt+j\n',
      accept: false,
    );
    expect(
      find.byKey(const Key('setting.global-hotkey.taken')),
      findsOneWidget,
    );
    expect(find.text('That shortcut is used by another app'), findsOneWidget);
    expect(
      find.byKey(const Key('setting.global-hotkey.warning')),
      findsNothing,
      reason: 'one line, not two',
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the problem panel says it in the same words', (t) async {
    final w = await openTerminalPage(
      t,
      config: 'global-hotkey = ctrl+alt+j\n',
      accept: false,
    );
    expect(
      w.container.read(shellxConfigProvider).runtimeProblems,
      hasLength(1),
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}

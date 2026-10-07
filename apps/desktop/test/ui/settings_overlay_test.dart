import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/shortcuts_sheet.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';
import 'package:shellx_desktop/src/ui/settings/settings_writer.dart';

import '../support/appearance_scroll.dart';
import '../support/config_harness.dart';
import '../support/config_workspace.dart';
import '../support/memory_config_fs.dart';

const cmd = LogicalKeyboardKey.metaLeft;
const alt = LogicalKeyboardKey.altLeft;

String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

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

final class OpenRecorder extends ConfigFileOpener {
  OpenRecorder() : super(windows: false);
  final opened = <String>[];

  @override
  Future<bool> open(String path, {required String Function() template}) async {
    opened.add(path);
    return true;
  }
}

typedef W = ({ProviderContainer container, MemoryConfigFs fs});

Future<W> openSettings(
  WidgetTester t, {
  String config = '',
  List<Override> extra = const [],
}) async {
  final w = await pumpConfiguredWorkspace(t, config: config, extra: extra);
  await chord(t, [cmd], LogicalKeyboardKey.comma);
  expect(find.byType(SettingsOverlay), findsOneWidget);
  return (container: w.container, fs: w.fs);
}

/// The button of an action row (the row's own centre is not the button).
Future<void> tapButton(WidgetTester t, String rowKey) async {
  final row = find.byKey(Key(rowKey));
  final button = find.descendant(
    of: row,
    matching: find.byType(OutlinedButton),
  );
  await t.tap(button);
  await t.pumpAndSettle();
}

Future<void> goTo(WidgetTester t, String page) async {
  await t.tap(find.byKey(Key('settings.page.$page')));
  await t.pumpAndSettle();
}

Future<void> submit(WidgetTester t, String key, String text) async {
  await t.enterText(find.byKey(Key(key)), text);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pumpAndSettle();
}

String shellxText(W w) => w.fs.text(testConfigPaths().shellx);

/// True when the keyboard is on something inside the widget [key].
bool focusIsIn(Key key) {
  final root = find.byKey(key).evaluate().single;
  var inside = false;
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  focus.visitAncestorElements((e) {
    if (identical(e, root)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('⌘, opens Settings on General; Esc closes; the terminal has the '
      'keyboard again (A10 F2)', (t) async {
    final w = await openSettings(t);
    expect(find.byKey(const Key('setting.launch-at-startup')), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(focusLabel(), isNot('terminal'));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the close button closes and gives the keyboard back', (t) async {
    final w = await openSettings(t);
    await t.tap(find.byKey(const Key('settings.close')));
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(focusLabel(), 'terminal');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the window shortcuts are off while Settings is open', (t) async {
    final w = await openSettings(t);
    final before = w.container.read(terminalTabsProvider).tabs.length;
    await chord(t, [cmd], LogicalKeyboardKey.keyT);
    expect(w.container.read(terminalTabsProvider).tabs.length, before);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('⌘⌥, opens the file, not Settings (A11 D10)', (t) async {
    final opener = OpenRecorder();
    final w = await pumpConfiguredWorkspace(
      t,
      extra: [configFileOpenerProvider.overrideWithValue(opener)],
    );
    await chord(t, [cmd, alt], LogicalKeyboardKey.comma);
    expect(opener.opened, [testConfigPaths().shellx]);
    expect(find.byType(SettingsOverlay), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('opening Settings and visiting every page writes nothing', (
    t,
  ) async {
    final w = await openSettings(t, config: '# mine\nfont-size = 14\n');
    final before = shellxText(w);
    for (final page in [
      'general',
      'appearance',
      'terminal',
      'keys',
      'agents',
      'phone',
      'advanced',
    ]) {
      await goTo(t, page);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(w.fs.replaced, isEmpty);
    expect(shellxText(w), before);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('with no file, opening and browsing creates none', (t) async {
    final w = await openSettings(t);
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await goTo(t, 'advanced');
    expect(w.fs.replaced, isEmpty);
    expect(w.fs.files.containsKey(testConfigPaths().shellx), isFalse);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('searching "cursor" leaves the cursor rows, with their page '
      'names', (t) async {
    final w = await openSettings(t);
    await t.enterText(find.byKey(const Key('settings.search')), 'cursor');
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('setting.cursor-style')), findsOneWidget);
    expect(find.byKey(const Key('setting.scrollback-limit')), findsNothing);
    expect(find.text('Appearance'), findsWidgets);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a Vietnamese keyword finds the row; a composing input method '
      'keeps searching and keeps Esc', (t) async {
    final w = await openSettings(t);
    final search = find.byKey(const Key('settings.search'));
    await t.enterText(search, 'nhấp nháy');
    await t.pump();
    expect(find.byKey(const Key('setting.cursor-style-blink')), findsOneWidget);
    // Telex: "tro" is still being composed.
    await t.showKeyboard(search);
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'cursor',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('setting.cursor-style')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsOneWidget); // the IME's Esc
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'cursor',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SettingsOverlay), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('no match shows the empty state with a file link', (t) async {
    final opener = OpenRecorder();
    final w = await openSettings(
      t,
      extra: [configFileOpenerProvider.overrideWithValue(opener)],
    );
    await t.enterText(find.byKey(const Key('settings.search')), 'zzzzqq');
    await t.pump(const Duration(milliseconds: 120));
    expect(find.text('No setting matches “zzzzqq”'), findsOneWidget);
    await t.tap(find.byKey(const Key('settings.no-match.open-file')));
    await t.pumpAndSettle();
    expect(opener.opened, [testConfigPaths().shellx]);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a hit\'s page name opens that page and lights the row', (
    t,
  ) async {
    final w = await openSettings(t);
    await t.enterText(find.byKey(const Key('settings.search')), 'scrollback');
    await t.pump(const Duration(milliseconds: 120));
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('setting.scrollback-limit')),
        matching: find.text('Terminal'),
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('settings.results')), findsNothing);
    expect(find.byKey(const Key('setting.scrollback-limit')), findsOneWidget);
    final box = t.widget<Container>(
      find.byKey(const Key('setting.scrollback-limit')),
    );
    expect((box.decoration! as BoxDecoration).color, isNot(Colors.transparent));
    await t.pump(const Duration(seconds: 2));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('typing a font size writes exactly that line, no other byte '
      'changes', (t) async {
    final w = await openSettings(t, config: '# mine\r\ntheme = Dracula\r\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '15');
    expect(shellxText(w), startsWith('# mine\r\ntheme = Dracula\r\n'));
    expect(shellxText(w), contains('font-size = 15\r\n'));
    expect(w.fs.replaced, hasLength(1));
    expect(w.container.read(shellxConfigProvider).config.fontSize, 15);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a user line is edited in place, not duplicated', (t) async {
    final w = await openSettings(t, config: 'font-size=13\ntheme = X\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '16');
    expect(shellxText(w), 'font-size=16\ntheme = X\n');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('leaving a field unchanged writes nothing', (t) async {
    final w = await openSettings(t, config: 'font-size = 13\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-family.field');
    await t.tap(find.byKey(const Key('setting.font-family.field')));
    await t.pump();
    await revealOnAppearance(t, 'setting.font-size.field');
    await submit(t, 'setting.font-size.field', '13');
    await goTo(t, 'terminal');
    expect(w.fs.replaced, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('an invalid value shows the parser\'s message and writes '
      'nothing', (t) async {
    final w = await openSettings(t, config: 'font-size = 13\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', 'abc');
    final error = find.byKey(const Key('setting.font-size.error'));
    expect(error, findsOneWidget);
    expect(t.widget<Text>(error).data, contains('is not valid'));
    expect(w.fs.replaced, isEmpty);
    // A screen reader hears it.
    final semantics = t.ensureSemantics();
    expect(t.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
    semantics.dispose();
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a value out of range is refused with the loader\'s hint', (
    t,
  ) async {
    final w = await openSettings(t);
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '99');
    expect(find.byKey(const Key('setting.font-size.error')), findsOneWidget);
    expect(w.fs.replaced, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a key set by an include is read-only with "Set in … line …"', (
    t,
  ) async {
    final w = await openSettings(t, config: 'config-file = /home/me/extra\n');
    w.fs.write('/home/me/extra', '# x\nfont-size = 18\n');
    await loadConfig(w.container);
    await t.pumpAndSettle();
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    expect(
      t.widget<Text>(find.byKey(const Key('setting.font-size.source'))).data,
      'Set in extra, line 2',
    );
    expect(
      t
          .widget<TextField>(find.byKey(const Key('setting.font-size.field')))
          .enabled,
      isFalse,
    );
    expect(find.byKey(const Key('setting.font-size.reset')), findsNothing);
    expect(
      find.byKey(const Key('setting.font-size.open-file')),
      findsOneWidget,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the file changing under the dialog refuses the write and '
      'reloads', (t) async {
    final w = await openSettings(t, config: 'theme = X\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    w.fs.beforeReplace = (path) {
      w.fs.beforeReplace = null;
      w.fs.write(path, '${w.fs.text(path)}# edited\n');
    };
    await submit(t, 'setting.font-size.field', '15');
    expect(shellxText(w), 'theme = X\n# edited\n');
    expect(
      w.container.read(terminalTabsProvider).notice,
      isA<SettingsFileChangedNotice>(),
    );
    expect(
      find.text(
        'The file changed while you were editing. Reloaded, try again.',
      ),
      findsWidgets,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a damaged managed block refuses the write', (t) async {
    final w = await openSettings(
      t,
      config: '# >>> shellx-managed settings >>>\nfont-size = 13\n',
    );
    final before = shellxText(w);
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '15');
    expect(shellxText(w), before);
    expect(
      w.container.read(terminalTabsProvider).notice,
      isA<SettingsFileDamagedNotice>(),
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a locked file (the OS refuses) shows the notice, no crash', (
    t,
  ) async {
    final w = await openSettings(t, config: 'theme = X\n');
    w.fs.replaceError = const FileSystemException('locked');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '15');
    expect(
      w.container.read(terminalTabsProvider).notice,
      isA<SettingsFileUnwritableNotice>(),
    );
    expect(shellxText(w), 'theme = X\n');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Reset comments out the user line and the row shows the '
      'default', (t) async {
    final w = await openSettings(t, config: 'font-size = 18\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    expect(
      t
          .widget<TextField>(find.byKey(const Key('setting.font-size.field')))
          .controller!
          .text,
      '18',
    );
    await t.tap(find.byKey(const Key('setting.font-size.reset')));
    await t.pumpAndSettle();
    expect(shellxText(w), '# font-size = 18\n');
    expect(
      t
          .widget<TextField>(find.byKey(const Key('setting.font-size.field')))
          .controller!
          .text,
      '13',
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Undo everything removes only our block, after a confirm', (
    t,
  ) async {
    final w = await openSettings(t, config: '# mine\ntheme = X\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '15');
    expect(shellxText(w), contains('shellx-managed settings'));
    await goTo(t, 'advanced');
    await t.tap(find.byKey(const Key('settings.reset-all')));
    await t.pumpAndSettle();
    // Cancel first: nothing happens.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(shellxText(w), contains('font-size = 15'));
    await t.tap(find.byKey(const Key('settings.reset-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('settings.reset-all.confirm')));
    await t.pumpAndSettle();
    // Only our block goes: the blank line that set it apart stays.
    expect(shellxText(w), '# mine\ntheme = X\n\n');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the Keys page holds the shortcut editor and lists the user '
      'commands', (t) async {
    final w = await openSettings(t, config: 'command = Lint = npm run lint\n');
    await goTo(t, 'keys');
    expect(find.byType(ShortcutsEditor), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('settings.commands-note'))).data,
      contains('Lint'),
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Advanced: path, problems, reload', (t) async {
    final w = await openSettings(t, config: 'font-size = to\n');
    await goTo(t, 'advanced');
    expect(find.text(testConfigPaths().shellx), findsOneWidget);
    expect(find.text('1 configuration problems'), findsWidgets);
    final before = w.container.read(shellxConfigProvider).generation;
    await tapButton(t, 'settings.reload');
    await t.pumpAndSettle();
    expect(w.container.read(shellxConfigProvider).generation, before + 1);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('keyboard: the search has the first focus, Tab walks the page '
      'list in order, Enter opens a page', (t) async {
    final w = await openSettings(t);
    expect(focusIsIn(const Key('settings.search')), isTrue);
    Future<void> tabTo(String page) async {
      // The scrolling list itself is one stop on the way in.
      for (var i = 0; i < 3 && !focusIsIn(Key('settings.page.$page')); i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
      }
      expect(focusIsIn(Key('settings.page.$page')), isTrue, reason: page);
    }

    await tabTo('general');
    await tabTo('appearance');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('preview.terminal')), findsOneWidget);
    // Shift+Tab goes back the way it came.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(focusIsIn(const Key('settings.page.general')), isTrue);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('⌘F and "/" jump to the search', (t) async {
    final w = await openSettings(t);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(focusIsIn(const Key('settings.search')), isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.slash);
    await t.pump();
    expect(focusIsIn(const Key('settings.search')), isTrue);
    // Typing "/" in the field is text, not a jump.
    await t.enterText(find.byKey(const Key('settings.search')), 'a/b');
    expect(
      t
          .widget<TextField>(find.byKey(const Key('settings.search')))
          .controller!
          .text,
      'a/b',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await chord(t, [cmd], LogicalKeyboardKey.keyF);
    expect(focusIsIn(const Key('settings.search')), isTrue);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a narrow window turns the page list into a tab strip', (
    t,
  ) async {
    final w = await openSettings(t);
    t.view.physicalSize = const Size(600, 700);
    await t.pumpAndSettle();
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    expect(find.byKey(const Key('preview.terminal')), findsOneWidget);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the overlay is a labelled route for a screen reader', (t) async {
    final handle = t.ensureSemantics();
    final w = await openSettings(t);
    final node = t.getSemantics(find.byType(SettingsOverlay));
    expect(node.label, contains('Settings'));
    expect(node.flagsCollection.scopesRoute, isTrue);
    handle.dispose();
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a commit writes no value into the log (privacy)', (t) async {
    final log = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => log.add(message ?? '');
    final w = await openSettings(t, config: 'font-size = 13\nfoo-bar = 1\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    await submit(t, 'setting.font-size.field', '15');
    await submit(t, 'setting.font-size.field', 'abc');
    w.fs.replaceError = const FileSystemException('x /home/me/secret');
    await submit(t, 'setting.font-size.field', '16');
    debugPrint = original;
    final all = log.join('\n');
    expect(all, isNot(contains('font-size = 15')));
    expect(all, isNot(contains('15')));
    expect(all, isNot(contains('abc')));
    expect(all, isNot(contains('secret')));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a slider writes on release only', (t) async {
    final w = await openSettings(t, config: 'font-size = 13\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    final slider = find.byKey(const Key('setting.font-size.slider'));
    final gesture = await t.startGesture(t.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await t.pump();
    await gesture.moveBy(const Offset(20, 0));
    // Held down for longer than the keyboard's debounce: still nothing.
    await t.pump(const Duration(milliseconds: 600));
    expect(w.fs.replaced, isEmpty);
    await gesture.up();
    await t.pumpAndSettle();
    expect(w.fs.replaced, hasLength(1));
    expect(w.container.read(shellxConfigProvider).config.fontSize, isNot(13.0));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('keyboard steps on a slider write once, 300 ms after the last', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    final w = await openSettings(t, config: 'font-size = 13\n');
    await goTo(t, 'appearance');
    await revealOnAppearance(t, 'setting.font-size');
    final slider = find.byKey(const Key('setting.font-size.slider'));
    // ignore: deprecated_member_use
    final owner = t.binding.pipelineOwner.semanticsOwner!;
    void increase(Finder f) =>
        owner.performAction(t.getSemantics(f).id, SemanticsAction.increase);
    increase(slider);
    await t.pump(const Duration(milliseconds: 100));
    increase(slider);
    await t.pump(const Duration(milliseconds: 200));
    expect(w.fs.replaced, isEmpty);
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(w.fs.replaced, hasLength(1));
    expect(w.container.read(shellxConfigProvider).config.fontSize, 14);
    handle.dispose();
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the writer refuses an edit that would add an error', (t) async {
    final w = await openSettings(t, config: 'font-size = to\n');
    final writer = w.container.read(settingsWriterProvider);
    // An existing error is not new: the edit goes through.
    var r = await writer.write((text) => '$text# note\n');
    expect(r, isA<Saved>());
    // A line the loader rejects is new: refused, the file as it was.
    final before = shellxText(w);
    r = await writer.write((text) => '${text}no equals sign here\n');
    expect(r, isA<Invalid>());
    expect(shellxText(w), before);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Windows: Option as Alt is not offered; macOS offers it', (
    t,
  ) async {
    final w = await openSettings(t);
    await goTo(t, 'terminal');
    expect(
      find.byKey(const Key('setting.macos-option-as-alt')),
      findsOneWidget,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets(
    'Windows: Ctrl+, opens Settings, Option as Alt is absent',
    (t) async {
      final w = await pumpConfiguredWorkspace(t);
      await chord(t, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.comma);
      expect(find.byType(SettingsOverlay), findsOneWidget);
      await goTo(t, 'terminal');
      expect(
        find.byKey(const Key('setting.macos-option-as-alt')),
        findsNothing,
      );
      await disposeWorkspace(t, w.container);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

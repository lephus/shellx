import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/font_probe.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/terminal/terminal_appearance.dart';
import 'package:shellx_desktop/src/terminal/terminal_style.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';
import 'package:shellx_desktop/src/ui/settings/settings_preview.dart';
import 'package:xterm/xterm.dart';

import '../support/appearance_scroll.dart';
import '../support/config_harness.dart';
import '../support/config_workspace.dart';
import '../support/memory_config_fs.dart';

const cmd = LogicalKeyboardKey.metaLeft;

typedef W = ({ProviderContainer container, MemoryConfigFs fs});

class _Probe implements FontProbe {
  @override
  ({bool found, bool monospace}) probe(String family) =>
      (found: false, monospace: true);
}

String get themeDir => testConfigPaths().themeDirs.first;

Future<W> openAppearance(
  WidgetTester t, {
  String config = '',
  List<Override> extra = const [],
  List<String> themes = const ['Nord', 'Dracula'],
}) async {
  final fs = MemoryConfigFs();
  for (final name in themes) {
    fs.write('$themeDir/$name', 'background = #101010\nforeground = #eeeeee\n');
  }
  // pumpConfiguredWorkspace builds its own fs: put the themes in after.
  final w = await pumpConfiguredWorkspace(t, config: config, extra: extra);
  for (final name in themes) {
    w.fs.write(
      '$themeDir/$name',
      'background = #${name == 'Nord' ? '2e3440' : '282a36'}\n'
          'foreground = #eeeeee\n',
    );
  }
  await t.sendKeyDownEvent(cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(cmd);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('settings.page.appearance')));
  await t.pumpAndSettle();
  return (container: w.container, fs: w.fs);
}

TerminalView sample(WidgetTester t) => t.widget<TerminalView>(
  find.descendant(
    of: find.byKey(const Key('preview.terminal')),
    matching: find.byType(TerminalView),
  ),
);

bool focusIsIn(Key key) {
  final root = find.byKey(key).evaluate().single;
  var inside = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    if (identical(e, root)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> reveal(WidgetTester t, String key) => revealOnAppearance(t, key);

Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

/// The keyboard on the theme row [name] (Tab into the list, then arrows).
Future<void> focusThemeRow(WidgetTester t, String name) async {
  await t.tap(find.byKey(const Key('settings.theme.search')));
  await t.pump();
  for (var i = 0; i < 4 && !focusIsIn(const Key('theme.row.ShellX')); i++) {
    await key(t, LogicalKeyboardKey.tab);
  }
  for (var i = 0; i < 6 && !focusIsIn(Key('theme.row.$name')); i++) {
    await key(t, LogicalKeyboardKey.arrowDown);
  }
  expect(focusIsIn(Key('theme.row.$name')), isTrue, reason: name);
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('Appearance shows a read-only terminal sample', (t) async {
    final w = await openAppearance(t);
    expect(find.byKey(const Key('preview.terminal')), findsOneWidget);
    expect(sample(t).readOnly, isTrue);
    expect(sample(t).hardwareKeyboardOnly, isTrue);
    expect(w.fs.replaced, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the list has ShellX first and the themes of the folders', (
    t,
  ) async {
    final w = await openAppearance(t);
    expect(find.byKey(const Key('theme.row.ShellX')), findsOneWidget);
    expect(find.byKey(const Key('theme.row.Nord')), findsOneWidget);
    expect(find.byKey(const Key('theme.row.Dracula')), findsOneWidget);
    await t.enterText(find.byKey(const Key('settings.theme.search')), 'nor');
    await t.pump();
    expect(find.byKey(const Key('theme.row.Nord')), findsOneWidget);
    expect(find.byKey(const Key('theme.row.Dracula')), findsNothing);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('focusing a theme previews it: no write, no real pane changes', (
    t,
  ) async {
    final w = await openAppearance(t, config: 'font-size = 14\n');
    final panesBefore = w.container.read(terminalAppearanceProvider);
    final backgroundBefore = sample(t).theme.background;
    await focusThemeRow(t, 'Nord');
    final preview = w.container.read(settingsPreviewProvider);
    expect(preview, isNotNull);
    expect(preview!.theme, 'Nord');
    await t.pumpAndSettle();
    expect(sample(t).theme.background, isNot(backgroundBefore));
    expect(w.fs.replaced, isEmpty);
    expect(w.container.read(terminalAppearanceProvider), panesBefore);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('hovering previews, leaving the list drops it', (t) async {
    final w = await openAppearance(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(t.getCenter(find.byKey(const Key('theme.row.Dracula'))));
    await t.pump();
    expect(w.container.read(settingsPreviewProvider)?.theme, 'Dracula');
    await mouse.moveTo(
      t.getCenter(find.byKey(const Key('settings.theme.search'))),
    );
    await t.pump();
    expect(w.container.read(settingsPreviewProvider), isNull);
    expect(w.fs.replaced, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Enter on a row writes "theme = Nord" once and ends the '
      'preview', (t) async {
    final w = await openAppearance(t, config: '# mine\n');
    await focusThemeRow(t, 'Nord');
    expect(w.fs.replaced, isEmpty);
    await key(t, LogicalKeyboardKey.enter);
    expect(w.fs.replaced, hasLength(1));
    expect(w.fs.text(testConfigPaths().shellx), startsWith('# mine\n'));
    expect(w.fs.text(testConfigPaths().shellx), contains('theme = Nord'));
    expect(w.container.read(settingsPreviewProvider), isNull);
    expect(w.container.read(shellxConfigProvider).config.theme, 'Nord');
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a click on a row writes the theme', (t) async {
    final w = await openAppearance(t);
    await t.tap(find.byKey(const Key('theme.row.Dracula')));
    await t.pumpAndSettle();
    expect(w.fs.text(testConfigPaths().shellx), contains('theme = Dracula'));
    expect(w.fs.replaced, hasLength(1));
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Esc with a previewed theme clears it and closes without '
      'writing', (t) async {
    final w = await openAppearance(t);
    await focusThemeRow(t, 'Nord');
    expect(w.container.read(settingsPreviewProvider)?.theme, 'Nord');
    await key(t, LogicalKeyboardKey.escape);
    expect(find.byType(SettingsOverlay), findsNothing);
    expect(w.container.read(settingsPreviewProvider), isNull);
    expect(w.fs.replaced, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('leaving the page drops the preview', (t) async {
    final w = await openAppearance(t);
    w.container.read(settingsPreviewProvider.notifier).preview(theme: 'Nord');
    await t.tap(find.byKey(const Key('settings.page.general')));
    await t.pumpAndSettle();
    expect(w.container.read(settingsPreviewProvider), isNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the font size follows a drag live and writes on release only', (
    t,
  ) async {
    final w = await openAppearance(t, config: 'font-size = 13\n');
    expect(sample(t).textStyle.fontSize, 13);
    await reveal(t, 'setting.font-size.slider');
    final slider = find.byKey(const Key('setting.font-size.slider'));
    final gesture = await t.startGesture(t.getCenter(slider));
    await gesture.moveBy(const Offset(60, 0));
    await t.pump();
    final during = sample(t).textStyle.fontSize;
    expect(during, greaterThan(13));
    expect(w.container.read(settingsPreviewProvider)?.fontSize, during);
    // The real panes keep their size meanwhile.
    expect(w.container.read(shellxConfigProvider).config.fontSize, 13);
    await gesture.moveBy(const Offset(20, 0));
    await t.pump(const Duration(milliseconds: 600));
    expect(w.fs.replaced, isEmpty);
    await gesture.up();
    await t.pumpAndSettle();
    expect(w.fs.replaced, hasLength(1));
    expect(
      w.container.read(shellxConfigProvider).config.fontSize,
      sample(t).textStyle.fontSize,
    );
    expect(w.container.read(settingsPreviewProvider), isNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('typing a size previews it (within 9–28) before Enter writes', (
    t,
  ) async {
    final w = await openAppearance(t, config: 'font-size = 13\n');
    await reveal(t, 'setting.font-size.field');
    await t.enterText(find.byKey(const Key('setting.font-size.field')), '20');
    await t.pump();
    expect(sample(t).textStyle.fontSize, 20);
    expect(w.fs.replaced, isEmpty);
    await t.enterText(find.byKey(const Key('setting.font-size.field')), '2');
    await t.pump();
    expect(sample(t).textStyle.fontSize, 9);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('the weight previews at once, then is written', (t) async {
    final w = await openAppearance(t);
    final seen = <PreviewState?>[];
    w.container.listen(settingsPreviewProvider, (_, s) => seen.add(s));
    expect(sample(t).textStyle.fontFamily, kTerminalFontFamilyLight);
    await reveal(t, 'setting.font-weight.opt.regular');
    await t.tap(find.byKey(const Key('setting.font-weight.opt.regular')));
    await t.pump();
    expect(seen.any((s) => s?.weight == TerminalFontWeight.regular), isTrue);
    await t.pumpAndSettle();
    expect(
      w.fs.text(testConfigPaths().shellx),
      contains('font-weight = regular'),
    );
    expect(w.fs.replaced, hasLength(1));
    expect(sample(t).textStyle.fontFamily, kTerminalFontFamily);
    expect(w.container.read(settingsPreviewProvider), isNull);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a theme whose file can\'t be read says so under the list', (
    t,
  ) async {
    final w = await openAppearance(t);
    w.container.read(settingsPreviewProvider.notifier).preview(theme: 'Ghost');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings.theme.error')), findsOneWidget);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('a font that is not installed is warned about after the save', (
    t,
  ) async {
    final w = await openAppearance(
      t,
      extra: [fontProbeProvider.overrideWithValue(_Probe())],
    );
    await reveal(t, 'setting.font-family.field');
    await t.enterText(
      find.byKey(const Key('setting.font-family.field')),
      'Nope Mono',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(
      w.fs.text(testConfigPaths().shellx),
      contains('font-family = Nope Mono'),
    );
    expect(
      find.byKey(const Key('setting.font-family.warning')),
      findsOneWidget,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  test('a preview never prints its values', () {
    expect(const PreviewState(theme: 'Secret', fontSize: 15).toString(), '…');
  });

  testWidgets('the preview merges what was previewed and clears as one', (
    t,
  ) async {
    final c = ProviderContainer.test();
    final n = c.read(settingsPreviewProvider.notifier);
    n.preview(theme: 'Nord');
    n.preview(fontSize: 18);
    expect(c.read(settingsPreviewProvider)?.theme, 'Nord');
    expect(c.read(settingsPreviewProvider)?.fontSize, 18);
    n.clearTheme();
    expect(c.read(settingsPreviewProvider)?.theme, isNull);
    expect(c.read(settingsPreviewProvider)?.fontSize, 18);
    n.clear();
    expect(c.read(settingsPreviewProvider), isNull);
  });
}

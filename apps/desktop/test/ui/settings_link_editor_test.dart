import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';

import '../support/config_workspace.dart';
import 'settings_agents_a12_test.dart' show reveal;
import 'settings_overlay_test.dart' show chord, goTo, openSettings, shellxText;

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('Terminal: the file-link editor row shows the five choices and '
      'writes link-editor', (t) async {
    final w = await openSettings(t);
    await goTo(t, 'terminal');
    final row = find.byKey(const Key('setting.link-editor'));
    await reveal(t, row);
    expect(find.text('Open file links in'), findsOneWidget);
    for (final v in ['auto', 'vscode', 'cursor', 'zed', 'finder']) {
      expect(find.byKey(Key('setting.link-editor.opt.$v')), findsOneWidget);
    }
    final auto = t.widget<ChoiceChip>(
      find.byKey(const Key('setting.link-editor.opt.auto')),
    );
    expect(auto.selected, isTrue);
    await t.tap(find.byKey(const Key('setting.link-editor.opt.cursor')));
    await t.pumpAndSettle();
    expect(shellxText(w), contains('link-editor = cursor'));
    expect(
      w.container.read(shellxConfigProvider).config.linkEditor,
      LinkEditor.cursor,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('Vietnamese labels', (t) async {
    final w = await pumpConfiguredWorkspace(t, locale: const Locale('vi'));
    await chord(t, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.comma);
    await goTo(t, 'terminal');
    await reveal(t, find.byKey(const Key('setting.link-editor')));
    expect(find.text('Mở liên kết tệp bằng'), findsOneWidget);
    expect(find.text('Tự động'), findsWidgets);
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}

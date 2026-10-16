import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/ai/ai_phone_reverts.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// V2-2b B19, R12: what the pane on the computer says of a phone's revert.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  test('the words, in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final vi = lookupAppLocalizations(const Locale('vi'));
    expect(en.aiRevertedFromPhone(1), 'Reverted 1 file (from your phone).');
    expect(en.aiRevertedFromPhone(2), 'Reverted 2 files (from your phone).');
    expect(vi.aiRevertedFromPhone(2), 'Đã hoàn tác 2 tệp (từ điện thoại).');
  });

  testWidgets('a phone\'s revert opens the pane\'s Changes panel on its note; '
      'another pane\'s is not its own', (t) async {
    final files = FakeProject(testAiCwd, {'a.txt': 'one\n'});
    files.onSnapshot = (ref) {
      if (ref.endsWith('/1')) files.files['a.txt'] = 'two\n';
    };
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Done.')],
        ],
      ),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    final c = w.container;
    final tab = openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsNothing);

    c.read(aiPhoneRevertsProvider).add((paneId: tab.ai!.id - 100, count: 9));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsNothing);

    c.read(aiPhoneRevertsProvider).add((paneId: tab.ai!.id, count: 2));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('ai.changes.note'))).data,
      'Reverted 2 files (from your phone).',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);
}

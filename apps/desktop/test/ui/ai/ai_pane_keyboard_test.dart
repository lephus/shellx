import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';
import 'ai_run_sheet_test.dart' show SheetPtys;

/// V2-1 §4.1: the AI pane moves the keyboard only when it is the pane's to
/// move — never out of a field the user is typing in elsewhere.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> openAgents(WidgetTester t, ProviderContainer c) async {
    c.read(settingsStartPageProvider.notifier).set(SettingPage.agents);
    c.read(configUiRequestProvider.notifier).request(ConfigUiRequest.settings);
    await t.pumpAndSettle();
    expect(find.byType(AgentsPage), findsOneWidget);
  }

  /// Scrolls Agents until [target] is built, then to it.
  Future<void> reveal(WidgetTester t, Finder target) async {
    final list = find
        .descendant(
          of: find.byType(AgentsPage),
          matching: find.byType(ListView),
        )
        .first;
    for (var n = 0; n < 24 && target.evaluate().isEmpty; n++) {
      await t.drag(list, const Offset(0, -200));
      await t.pump();
    }
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }

  /// A field of Settings › Agents with the keyboard.
  Future<FocusNode> typeInSettings(WidgetTester t) async {
    final field = find.byKey(const Key('ai.custom.name'));
    await reveal(t, field);
    await t.tap(field);
    await t.pump();
    final node = t
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .focusNode;
    expect(node.hasPrimaryFocus, isTrue);
    return node;
  }

  testWidgets('the agent switched off and on while the user types in '
      'Settings: the pane does not take the keyboard', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(fakes.made, hasLength(1));
    await openAgents(t, c);
    final name = await typeInSettings(t);
    // Off: the pane lets its runtime go; on: it makes a new one.
    w.fs.write(testConfigPaths().shellx, 'ai-agent-claude = off\n');
    await loadConfig(c);
    await t.pumpAndSettle();
    w.fs.write(testConfigPaths().shellx, 'ai-agent-claude = on\n');
    await loadConfig(c);
    await t.pumpAndSettle();
    expect(fakes.made, hasLength(2), reason: 'a new runtime was attached');
    expect(name.hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a sign-in that ends while the user is in Settings does not '
      'pull the keyboard into the composer', (t) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
        ],
      ),
    );
    final ptys = SheetPtys();
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [...fakes.overrides, aiPtyFactoryProvider.overrideWithValue(ptys)],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ai.login.login')));
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(1));
    await openAgents(t, c);
    final name = await typeInSettings(t);
    ptys.spawned.single.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(name.hasPrimaryFocus, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);
}

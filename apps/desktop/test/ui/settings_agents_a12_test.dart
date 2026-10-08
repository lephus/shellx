import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/integrations/integration_probe.dart';
import 'package:shellx_desktop/src/integrations/integration_status.dart';
import 'package:shellx_desktop/src/integrations/pr_status.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/settings/settings_overlay.dart';

import '../integrations/integration_probe_test.dart' show FakeFs, hooks;
import '../support/config_harness.dart';
import '../support/config_workspace.dart';

const cmd = LogicalKeyboardKey.metaLeft;

typedef Rig = ({
  ProviderContainer container,
  FakeFs fs,
  dynamic local,
  dynamic config,
});

Future<Rig> openAgents(
  WidgetTester t, {
  Locale locale = const Locale('en'),
  FakeFs? fs,
  String? binary = '/cli/shellx',
  String config = '',
  List<Override> extra = const [],
}) async {
  final files = fs ?? FakeFs();
  final w = await pumpConfiguredWorkspace(
    t,
    locale: locale,
    config: config,
    extra: [
      integrationProbeProvider.overrideWithValue(
        IntegrationProbe(fs: files, env: const {}, home: '/h', windows: false),
      ),
      shellxBinaryProvider.overrideWithValue(() async => binary),
      ...extra,
    ],
  );
  await t.sendKeyDownEvent(cmd);
  await t.sendKeyEvent(LogicalKeyboardKey.comma);
  await t.sendKeyUpEvent(cmd);
  await t.pumpAndSettle();
  expect(find.byType(SettingsOverlay), findsOneWidget);
  await t.tap(find.byKey(const Key('settings.page.agents')));
  await t.pumpAndSettle();
  await reveal(t, row('opencode'));
  return (container: w.container, fs: files, local: w.local, config: w.fs);
}

/// Scrolls Settings until [target] is built (the page is a lazy list).
Future<void> reveal(WidgetTester t, Finder target) async {
  final list = find
      .descendant(
        of: find.byType(SettingsOverlay),
        matching: find.byType(ListView),
      )
      .last;
  for (var n = 0; n < 24 && target.evaluate().isEmpty; n++) {
    await t.drag(list, Offset(0, n < 12 ? -200 : 200));
    await t.pump();
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Finder row(String agent) => find.byKey(Key('integration.row.$agent'));
Finder chip(String agent, String text) =>
    find.descendant(of: row(agent), matching: find.text(text));

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('four rows, a chip each; Codex says what it cannot report', (
    t,
  ) async {
    final fs = FakeFs()
      ..files['/h/.claude/settings.json'] = hooks('claude')
      ..dirs.addAll(['/h/.claude', '/h/.codex', '/h/.gemini']);
    final r = await openAgents(t, fs: fs);
    await reveal(t, find.text('AGENT INTEGRATIONS'));
    expect(find.text('AGENT INTEGRATIONS'), findsOneWidget);
    for (final a in ['claude', 'codex', 'gemini', 'opencode']) {
      expect(row(a), findsOneWidget, reason: a);
    }
    expect(chip('claude', 'Installed'), findsOneWidget);
    expect(chip('codex', 'Not installed'), findsOneWidget);
    expect(chip('gemini', 'Not installed'), findsOneWidget);
    expect(chip('opencode', 'Not installed'), findsOneWidget);
    expect(
      find.descendant(
        of: row('codex'),
        matching: find.text(
          'Codex reports when a turn ends; it does not report “running”.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('claude'),
        matching: find.textContaining('Codex reports'),
      ),
      findsNothing,
    );
    // Never found anywhere: said, only for the one with no folder and no
    // program.
    expect(
      find.descendant(
        of: row('opencode'),
        matching: find.text('OpenCode not found on this computer'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row('gemini'),
        matching: find.textContaining('not found'),
      ),
      findsNothing,
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('Vietnamese', (t) async {
    final r = await openAgents(t, locale: const Locale('vi'));
    await reveal(t, find.text('TÍCH HỢP AGENT'));
    expect(find.text('TÍCH HỢP AGENT'), findsOneWidget);
    expect(chip('claude', 'Chưa cài'), findsOneWidget);
    expect(find.text('Cài đặt trong terminal'), findsWidgets);
    expect(
      find.descendant(
        of: row('codex'),
        matching: find.text(
          'Codex chỉ báo khi một lượt kết thúc, không báo “đang chạy”.',
        ),
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('opening the page writes nothing: no config, no agent file', (
    t,
  ) async {
    final r = await openAgents(t);
    expect(r.config.files, isEmpty);
    expect(r.config.replaced, isEmpty);
    expect(r.fs.files, isEmpty);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('Set up opens one new tab and types exactly the command; '
      'Settings closes so the tab shows', (t) async {
    final r = await openAgents(t);
    final before = r.container.read(terminalTabsProvider).tabs.length;
    final button = find.descendant(
      of: row('claude'),
      matching: find.byKey(const Key('integration.setup.claude')),
    );
    await reveal(t, button);
    await t.tap(button);
    await t.pumpAndSettle();
    final state = r.container.read(terminalTabsProvider);
    expect(state.tabs.length, before + 1);
    final tab = state.selected!;
    expect(tab.id, state.tabs.last.id);
    await t.pump(const Duration(seconds: 10));
    final typed = r.local.views[tab.focusedPaneId]!.writes.join();
    expect(
      '/cli/shellx integrations install claude'.allMatches(typed),
      hasLength(1),
    );
    expect(typed, isNot(contains('--yes')));
    expect(typed, isNot(contains('-y')));
    expect(find.byType(SettingsOverlay), findsNothing);
    // The press asked nothing of the agent's files.
    expect(r.fs.files, isEmpty);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('an installed agent offers Remove, which uninstalls in a tab', (
    t,
  ) async {
    final fs = FakeFs()..files['/h/.gemini/settings.json'] = hooks('gemini');
    final r = await openAgents(t, fs: fs);
    expect(find.byKey(const Key('integration.setup.gemini')), findsNothing);
    final button = find.byKey(const Key('integration.remove.gemini'));
    await reveal(t, button);
    expect(
      find.descendant(of: button, matching: find.text('Remove in a terminal')),
      findsOneWidget,
    );
    await t.tap(button);
    await t.pumpAndSettle();
    final tab = r.container.read(terminalTabsProvider).selected!;
    await t.pump(const Duration(seconds: 10));
    expect(
      r.local.views[tab.focusedPaneId]!.writes.join(),
      contains('/cli/shellx integrations uninstall gemini'),
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the status is read again when that tab closes', (t) async {
    final r = await openAgents(t);
    expect(
      r.container.read(integrationStatusProvider)![AgentKind.claude]!.installed,
      isFalse,
    );
    final button = find.byKey(const Key('integration.setup.claude'));
    await reveal(t, button);
    await t.tap(button);
    await t.pumpAndSettle();
    final tab = r.container.read(terminalTabsProvider).selected!;
    // The CLI installed it in that tab.
    r.fs.files['/h/.claude/settings.json'] = hooks('claude');
    await t.pumpAndSettle();
    expect(
      r.container.read(integrationStatusProvider)![AgentKind.claude]!.installed,
      isFalse,
      reason: 'not while the tab is open',
    );
    r.container.read(terminalTabsProvider.notifier).close(tab.id);
    await t.pumpAndSettle();
    expect(
      r.container.read(integrationStatusProvider)![AgentKind.claude]!.installed,
      isTrue,
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('a probe that throws shows "not installed" and logs nothing', (
    t,
  ) async {
    final log = <String>[];
    final saved = debugPrint;
    debugPrint = (m, {wrapWidth}) => log.add(m ?? '');
    final fs = FakeFs()..readError = StateError('/secret/path');
    final r = await openAgents(t, fs: fs);
    expect(chip('claude', 'Not installed'), findsOneWidget);
    debugPrint = saved;
    expect(log.where((l) => l.contains('secret')), isEmpty);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the resume switch is on this page and writes the key', (
    t,
  ) async {
    final r = await openAgents(t);
    final row = find.byKey(const Key('setting.agent-resume'));
    await reveal(t, row);
    expect(find.text('Offer to resume agent sessions'), findsOneWidget);
    await t.tap(find.descendant(of: row, matching: find.text('Off')));
    await t.pumpAndSettle();
    expect(
      r.config.text(testConfigPaths().shellx),
      contains('agent-resume = off'),
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the pull request switch is off by default and writes the key', (
    t,
  ) async {
    final r = await openAgents(t);
    final row = find.byKey(const Key('setting.pr-status'));
    await reveal(t, row);
    expect(find.text('Show pull request status'), findsOneWidget);
    expect(find.textContaining('never reads your token'), findsOneWidget);
    expect(r.container.read(shellxConfigProvider).config.prStatus, isFalse);
    await t.tap(find.byKey(const Key('setting.pr-status.switch')));
    await t.pumpAndSettle();
    expect(
      r.config.text(testConfigPaths().shellx),
      contains('pr-status = true'),
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('on, without gh: the row says gh was not found', (t) async {
    final r = await openAgents(
      t,
      config: 'pr-status = true\n',
      extra: [ghFinderProvider.overrideWithValue(() async => null)],
    );
    await reveal(t, find.byKey(const Key('setting.pr-status')));
    expect(find.text('GitHub CLI (gh) was not found.'), findsOneWidget);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('Vietnamese: the pull request row', (t) async {
    final r = await openAgents(t, locale: const Locale('vi'));
    await reveal(t, find.byKey(const Key('setting.pr-status')));
    expect(find.text('Hiện trạng thái pull request'), findsOneWidget);
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('the shellx command is typed by its absolute path, quoted for '
      'the shell', (t) async {
    final r = await openAgents(
      t,
      binary: '/Users/me/Library/App Support/cli/shellx',
    );
    final button = find.byKey(const Key('integration.setup.claude'));
    await reveal(t, button);
    await t.tap(button);
    await t.pumpAndSettle();
    final tab = r.container.read(terminalTabsProvider).selected!;
    await t.pump(const Duration(seconds: 10));
    expect(
      r.local.views[tab.focusedPaneId]!.writes.join(),
      contains(
        "/Users/me/Library/App\\ Support/cli/shellx integrations install claude",
      ),
    );
    await disposeWorkspace(t, r.container);
  }, variant: mac);

  testWidgets('without the shellx command, Set up is disabled and says '
      'where to install it', (t) async {
    final r = await openAgents(t, binary: null);
    final before = r.container.read(terminalTabsProvider).tabs.length;
    await reveal(t, find.byKey(const Key('integration.setup.claude')));
    expect(
      t
          .widget<OutlinedButton>(
            find.byKey(const Key('integration.setup.claude')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Install the shellx command first (Settings › Command line)'),
      findsWidgets,
    );
    await t.tap(
      find.byKey(const Key('integration.setup.claude')),
      warnIfMissed: false,
    );
    await t.pumpAndSettle();
    expect(r.container.read(terminalTabsProvider).tabs.length, before);
    await disposeWorkspace(t, r.container);
  }, variant: mac);
}

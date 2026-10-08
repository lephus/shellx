import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_controller.dart';
import 'package:shellx_desktop/src/integrations/agent_command_runner.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart'
    show homeDirectoryProvider;
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/config_harness.dart';
import '../support/config_workspace.dart';

final class _Proc implements Process {
  _Proc() : stdin = IOSink(StreamController<List<int>>());
  @override
  final IOSink stdin;
  final _exit = Completer<int>();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-9);
    return true;
  }
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  const command = '~/bin/on-agent --fast';
  var now = DateTime.utc(2026, 10, 8, 9);

  Future<({dynamic c, dynamic fs, List<List<String>> runs, int pane})> boot(
    WidgetTester t, {
    String config = 'agent-event-command = $command\n',
    Locale locale = const Locale('en'),
  }) async {
    final runs = <List<String>>[];
    now = DateTime.utc(2026, 10, 8, 9);
    final w = await pumpConfiguredWorkspace(
      t,
      config: config,
      locale: locale,
      extra: [
        agentStatusClockProvider.overrideWithValue(() => now),
        homeDirectoryProvider.overrideWithValue('/Users/me'),
        agentCommandKillTreeProvider.overrideWithValue((p) async {
          p.kill();
        }),
        agentCommandStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
          includeParentEnvironment = true,
          runInShell = false,
        }) async {
          runs.add([exe, ...args]);
          return _Proc();
        }),
      ],
    );
    final pane = w.container.read(terminalTabsProvider).selected!.id;
    return (c: w.container, fs: w.fs, runs: runs, pane: pane);
  }

  void send(dynamic c, int pane, AgentEventKind kind, [int s = 0]) {
    (c.read(agentStatusProvider.notifier) as AgentStatusNotifier).ingest(
      AgentEvent(
        pane: pane,
        agent: AgentKind.claude,
        kind: kind,
        at: now.add(Duration(seconds: s)),
      ),
    );
  }

  testWidgets('not allowed: nothing runs; a notice with a button; the dialog '
      'shows the exact string; Allow stores the hash and the next event '
      'runs it once', (t) async {
    final r = await boot(t);
    send(r.c, r.pane, AgentEventKind.needsInput);
    await t.pump();
    await t.pump();
    expect(r.runs, isEmpty);
    expect(
      find.text('An agent-event command is set but not allowed yet.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('pane.toast.action')));
    await t.pump();
    final request = r.c.read(windowRouterProvider).confirm as ConfirmRequest;
    expect(request.title, 'Allow this command?');
    // The exact words, one per line, in a monospace block.
    expect(request.code, ['/Users/me/bin/on-agent', '--fast'].join('\n'));
    expect(request.body, isNot(contains('on-agent')));
    expect(request.confirmLabel, 'Allow');
    expect(request.cancelLabel, 'Cancel');
    expect(request.destructive, isTrue); // starts on Cancel
    request.complete(true);
    await t.pump();
    await t.pump();
    final store = r.c.read(settingsStoreProvider) as InMemorySettingsStore;
    expect(store.strings[SettingKeys.agentCommandApproved], [
      commandHash(command),
    ]);
    expect(
      store.strings.values.expand((v) => v).join(),
      isNot(contains('on-agent')),
    );
    now = now.add(const Duration(seconds: 2));
    send(r.c, r.pane, AgentEventKind.running, 2);
    await t.pump();
    await t.pump();
    expect(r.runs, hasLength(1));
    expect(r.runs.single.first, endsWith('/bin/on-agent'));
    expect(r.runs.single.skip(1), ['--fast']);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('Cancel stores nothing and the next event asks nothing more', (
    t,
  ) async {
    final r = await boot(t);
    send(r.c, r.pane, AgentEventKind.needsInput);
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(const Key('pane.toast.action')));
    await t.pump();
    (r.c.read(windowRouterProvider).confirm as ConfirmRequest).complete(false);
    await t.pump();
    final store = r.c.read(settingsStoreProvider) as InMemorySettingsStore;
    expect(store.strings[SettingKeys.agentCommandApproved], isNull);
    send(r.c, r.pane, AgentEventKind.running, 3);
    await t.pump();
    expect(r.runs, isEmpty);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('a changed string asks again', (t) async {
    final r = await boot(t);
    final store = r.c.read(settingsStoreProvider) as InMemorySettingsStore;
    await approveCommand(store, commandHash(command));
    send(r.c, r.pane, AgentEventKind.running);
    await t.pump();
    await t.pump();
    expect(r.runs, hasLength(1));
    expect(
      find.text('An agent-event command is set but not allowed yet.'),
      findsNothing,
    );
    r.fs.write(
      testConfigPaths().shellx,
      'agent-event-command = $command --more\n',
    );
    await loadConfig(r.c);
    now = now.add(const Duration(seconds: 3));
    send(r.c, r.pane, AgentEventKind.needsInput, 3);
    await t.pump();
    await t.pump();
    expect(r.runs, hasLength(1));
    expect(
      find.text('An agent-event command is set but not allowed yet.'),
      findsOneWidget,
    );
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('no command set: no notice, nothing runs', (t) async {
    final r = await boot(t, config: '');
    send(r.c, r.pane, AgentEventKind.needsInput);
    await t.pump();
    await t.pump();
    expect(r.runs, isEmpty);
    expect(find.byKey(const Key('pane.toast')), findsNothing);
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('Vietnamese notice and dialog', (t) async {
    final r = await boot(t, locale: const Locale('vi'));
    send(r.c, r.pane, AgentEventKind.needsInput);
    await t.pump();
    await t.pump();
    expect(
      find.text('Đã đặt lệnh sự kiện agent nhưng chưa được cho phép.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('pane.toast.action')));
    await t.pump();
    final request = r.c.read(windowRouterProvider).confirm as ConfirmRequest;
    expect(request.title, 'Cho phép lệnh này?');
    expect(request.confirmLabel, 'Cho phép');
    request.complete(false);
    await t.pump();
    await disposeWorkspace(t, r.c);
  }, variant: mac);

  testWidgets('a command from an include is ignored, with a problem', (
    t,
  ) async {
    final w = await pumpConfiguredWorkspace(
      t,
      config: 'config-file = /home/me/extra\n',
    );
    w.fs.write('/home/me/extra', 'agent-event-command = /tmp/evil\n');
    await loadConfig(w.container);
    expect(w.container.read(shellxConfigProvider).config.agentEventCommand, '');
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}

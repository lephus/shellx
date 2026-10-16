import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' hide AgentEvent;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/resume_offers.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/config_harness.dart';
import '../support/fake_local_sessions.dart';
import '../support/memory_config_fs.dart';
import '../support/restore_fakes.dart';

final k1 = '1' * 32, k2 = '2' * 32;
const claude = (kind: AgentKind.claude, session: 'abc');

void main() {
  late FakeLocalSessions local;
  late RecordingFiles files;
  late ProviderContainer c;
  late List<String> log;

  void boot({String config = ''}) {
    final fs = MemoryConfigFs();
    if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 15)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        ...configOverrides(fs),
      ],
    );
    c.read(sidebarWorkspacesProvider);
  }

  RestoreSnapshot snapshot({
    String? cwd = '/w',
    SessionLaunch? launch,
    ({AgentKind kind, String session})? agent = claude,
    int? session,
    String? daemon,
  }) => RestoreSnapshot(
    savedAt: DateTime(2026, 10, 7, 14, 31),
    cleanExit: false,
    daemon: daemon,
    selectedTab: k1,
    workspaces: [
      SavedWorkspace(id: 'default', tabs: [k1]),
    ],
    tabs: [
      SavedTab(
        key: k1,
        focused: k1,
        layout: SavedPane(
          key: k1,
          cwd: cwd,
          launch: launch,
          agent: agent,
          session: session,
        ),
      ),
    ],
  );

  Future<void> restore(RestoreSnapshot s, {String? daemonInstance}) async {
    await loadConfig(c);
    await c
        .read(restorePersistenceProvider.notifier)
        .restoreAtStartup(
          RestoreLoad(snapshot: s),
          daemonInstance: daemonInstance,
        );
  }

  Map<int, ResumeOffer> offers() => c.read(resumeOffersProvider);

  setUp(() {
    log = [];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => log.add(message ?? '');
    addTearDown(() => debugPrint = print);
    local = FakeLocalSessions();
    files = RecordingFiles();
  });

  test('a plain restore offers to resume a pane with an agent and a folder; '
      'nothing is typed', () async {
    boot();
    await restore(snapshot());
    final pane = c.read(terminalTabsProvider).tabs.single.focusedPaneId;
    expect(offers().keys, [pane]);
    expect(offers()[pane]!.kind, AgentKind.claude);
    expect(offers()[pane]!.session, 'abc');
    expect(local.views[pane]!.writes, isEmpty);
    // The id is kept as an unseen record, so another crash still has it.
    final record = c.read(agentStatusProvider)[pane]!;
    expect(record.state, AgentState.unknown);
    expect(record.session, 'abc');
    expect(agentStateVisible(record.state), isFalse);
  });

  test('agent-resume = off: no offer, and no record either', () async {
    boot(config: 'agent-resume = off\n');
    await restore(snapshot());
    expect(offers(), isEmpty);
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('reattach: no offer, the record is restored as unknown and saved '
      'again at the next snapshot', () async {
    local.add(local.summary(5, origin: SessionOrigin.desktop), notify: false);
    boot();
    c.read(restorePersistenceProvider.notifier).start();
    await restore(snapshot(session: 5, daemon: 'i1'), daemonInstance: 'i1');
    expect(offers(), isEmpty);
    final record = c.read(agentStatusProvider)[5]!;
    expect(record.state, AgentState.unknown);
    expect(record.agent, AgentKind.claude);
    expect(record.session, 'abc');
    await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
    final pane = files.layouts.last.tabs.single.layout as SavedPane;
    expect(pane.agent, claude);
  });

  test('an SSH or tmux pane (launch) gets no offer', () async {
    boot();
    await restore(snapshot(launch: SshLaunch(SshTarget.parse('devbox')!)));
    expect(offers(), isEmpty);
  });

  test('a pane whose folder was not restored gets no offer', () async {
    boot();
    await restore(snapshot(cwd: null));
    expect(offers(), isEmpty);
  });

  test('a pane without an agent gets none', () async {
    boot();
    await restore(snapshot(agent: null));
    expect(offers(), isEmpty);
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('dismiss clears the offer and the unseen record; resume keeps only '
      'what the next event replaces', () async {
    boot();
    await restore(snapshot());
    final pane = offers().keys.single;
    c.read(resumeOffersProvider.notifier).dismiss(pane);
    expect(offers(), isEmpty);
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('the first key typed into the pane removes the offer and the '
      'record', () async {
    boot();
    await restore(snapshot());
    final pane = offers().keys.single;
    c
        .read(terminalTabsProvider)
        .tabOfSession(pane)!
        .panes[pane]!
        .terminal
        .onUserInput!('x');
    expect(offers(), isEmpty);
    expect(c.read(agentStatusProvider), isEmpty);
  });

  test('closing the pane removes its offer', () async {
    boot();
    await restore(snapshot());
    final pane = offers().keys.single;
    c.read(terminalTabsProvider.notifier).close(pane);
    expect(offers(), isEmpty);
  });

  test('an agent that started in the pane meanwhile ends the offer', () async {
    boot();
    await restore(snapshot());
    final pane = offers().keys.single;
    c
        .read(agentStatusProvider.notifier)
        .ingest(
          AgentEvent(
            pane: pane,
            agent: AgentKind.claude,
            kind: AgentEventKind.start,
            at: DateTime.now(),
            session: 'new-1',
          ),
        );
    expect(offers(), isEmpty);
    expect(c.read(agentStatusProvider)[pane]!.session, 'new-1');
  });

  test('nothing the agent said reaches a log', () async {
    boot();
    await restore(snapshot());
    c.read(resumeOffersProvider.notifier).dismiss(offers().keys.single);
    expect(log.where((l) => l.contains('abc')), isEmpty);
    expect(log.where((l) => l.contains('/w')), isEmpty);
  });

  group('saving', () {
    AgentEvent ev(int pane, AgentEventKind k, {String? session, int s = 0}) =>
        AgentEvent(
          pane: pane,
          agent: AgentKind.claude,
          kind: k,
          at: DateTime.now().add(Duration(seconds: s)),
          session: session,
        );

    SavedPane? savedPane(int i) =>
        files.layouts[i].tabs.single.layout as SavedPane?;

    test(
      'a session id appearing is saved (debounced), an end removes it '
      'again',
      () => fakeAsync((async) {
        local.add(local.summary(1));
        boot();
        c.read(restorePersistenceProvider.notifier).start();
        async.flushMicrotasks();
        c
            .read(agentStatusProvider.notifier)
            .ingest(ev(1, AgentEventKind.start, session: 'abc'));
        async.elapse(const Duration(seconds: 2));
        expect(savedPane(files.layouts.length - 1)!.agent, claude);
        final writes = files.layouts.length;
        // The id changes (a resumed or compacted session): written again.
        c
            .read(agentStatusProvider.notifier)
            .ingest(ev(1, AgentEventKind.running, session: 'def', s: 1));
        async.elapse(const Duration(seconds: 2));
        expect(files.layouts.length, writes + 1);
        expect(savedPane(files.layouts.length - 1)!.agent?.session, 'def');
        // A state change alone writes nothing.
        c
            .read(agentStatusProvider.notifier)
            .ingest(ev(1, AgentEventKind.idle, s: 2));
        async.elapse(const Duration(seconds: 2));
        expect(files.layouts.length, writes + 1);
        // The agent ended normally: not saved.
        c
            .read(agentStatusProvider.notifier)
            .ingest(ev(1, AgentEventKind.end, s: 3));
        async.elapse(const Duration(seconds: 2));
        expect(savedPane(files.layouts.length - 1)!.agent, isNull);
      }),
    );

    test(
      'a record without an id saves nothing',
      () => fakeAsync((async) {
        local.add(local.summary(1));
        boot();
        c.read(restorePersistenceProvider.notifier).start();
        async.flushMicrotasks();
        c
            .read(agentStatusProvider.notifier)
            .ingest(ev(1, AgentEventKind.running));
        async.elapse(const Duration(seconds: 2));
        for (var i = 0; i < files.layouts.length; i++) {
          expect(savedPane(i)!.agent, isNull);
        }
      }),
    );
  });
}

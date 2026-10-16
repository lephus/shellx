import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart' show FakeScenario;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_ports.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

final class _Probe implements PortProbe, ProcessTableProbe {
  _Probe(this.ports, this.rows);
  final Map<int, Set<int>> ports;
  final Map<int, ProgramRow> rows;
  int scans = 0;

  /// Thrown by the read of the listening sockets / of the process table.
  Object? listeningError;
  Object? tableError;

  @override
  Future<Map<int, Set<int>>> listening() async {
    scans++;
    final error = listeningError;
    if (error != null) throw error;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => const {};

  @override
  Future<Map<int, ProgramRow>> processTable() async {
    final error = tableError;
    if (error != null) throw error;
    return rows;
  }
}

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// [done], asked every 25 ms for up to 10 s: a process starting or ending
/// takes a moment, and the machine may be busy.
Future<bool> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return done();
}

/// `AiHost.runtime` (packages/shellx_ai/lib/src/host/ai_host.dart) as
/// `aiRuntimeFactoryProvider`'s copy of it was made (V2-3 R12). Update this
/// only after the copy follows a change of the original.
const _pinnedHostRuntime = r'''
AiRuntime runtime({
    required AgentSpec agent,
    required String cwd,
    String? resumeSessionId,
    Map<String, Object> preferredConfig = const {},
  }) => AiRuntime(
    state: AiSessionState(agentId: agent.id, agentName: agent.name, cwd: cwd),
    resolve: () async => resolver.resolve(agent, await env.resolve()),
    launch: launch,
    clientVersion: clientVersion,
    checkpoints: () async => checkpoints.forProject(cwd, await env.resolve()),
    resumeSessionId: resumeSessionId,
    preferredConfig: preferredConfig,
  );''';

const _hostRuntimeChanged =
    'AiHost.runtime changed (packages/shellx_ai/lib/src/host/ai_host.dart). '
    'The copy in aiRuntimeFactoryProvider '
    '(apps/desktop/lib/src/ai/ai_runtimes.dart) builds the runtime of every '
    'desktop AI pane: bring it in step with AiHost.runtime first, and only '
    'then update _pinnedHostRuntime in this test (V2-3 R12).';

/// [text] with every run of white space (a line break, indentation, a
/// Windows `\r\n`) as one space.
String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// `AiHost.runtime` in [source], from `AiRuntime runtime({` to its closing
/// `);`, squashed; null when it is not there.
String? _hostRuntimeIn(String source) {
  final start = source.indexOf('AiRuntime runtime({');
  if (start < 0) return null;
  final end = source.indexOf(');', start);
  if (end < 0) return null;
  return _squash(source.substring(start, end + 2));
}

final class _Channel implements AgentChannel {
  final _exit = Completer<int>();
  void end() => _exit.complete(0);
  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  StreamSink<List<int>> get stdin => StreamController<List<int>>().sink;
  @override
  String get stderrTail => '';
  @override
  Future<void> stop() async {}
  @override
  Future<void> kill() async {}
}

void main() {
  test('suggestions: panes and agents, named, without used ports, by port, '
      'at most 8 (D12)', () {
    final list = toolPortSuggestions(
      panePorts: {5173, 3000, 9000},
      agentPorts: const [
        (port: 4000, root: 1, name: 'node'),
        (port: 3000, root: 1, name: 'node'),
      ],
      nameOf: (p) => p == 5173 ? 'vite' : '',
      usedPorts: {9000},
    );
    expect(list, const [
      ToolPortSuggestion(port: 3000, process: 'node'),
      ToolPortSuggestion(port: 4000, process: 'node'),
      ToolPortSuggestion(port: 5173, process: 'vite'),
    ]);
    expect(list.first.url, 'http://localhost:3000/');
    final many = toolPortSuggestions(
      panePorts: {for (var p = 1; p <= 12; p++) p},
      usedPorts: const {},
    );
    expect(many.map((s) => s.port), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(many.first.toString(), 'ToolPortSuggestion(…)');
  });

  group('in a window', () {
    late FakeLocalSessions local;
    late ProviderContainer c;
    late _Probe probe;

    setUp(() {
      local = FakeLocalSessions();
      probe = _Probe(
        {
          100: {5173},
          903: {4000},
          50: {8080},
        },
        {
          100: (parent: 1, name: 'node'),
          900: (parent: 1, name: 'claude'),
          903: (parent: 900, name: 'node'),
          50: (parent: 1, name: 'nginx'),
        },
      );
      c = ProviderContainer.test(
        overrides: [
          localSessionsProvider.overrideWithValue(local),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 10, 15, 9)),
          appL10nProvider.overrideWithValue(
            lookupAppLocalizations(const Locale('en')),
          ),
          toolPortProbeProvider.overrideWithValue((ports: probe, table: probe)),
        ],
      );
      c.read(sidebarWorkspacesProvider);
    });

    test('a terminal pane\'s ports, and an AI agent\'s server, appear in '
        'one scan (D12, criterion 2)', () async {
      await c.read(terminalTabsProvider.notifier).openTab();
      final session = local.summaries.single.id;
      local.replace(local.summary(session, ports: [5173]));
      final ai = openTestAiTab(c, title: 'x', cwd: '/w');
      c.read(aiAgentPidsProvider).set(ai.ai!.id, 900);
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, const [
        ToolPortSuggestion(port: 4000, process: 'node'),
        ToolPortSuggestion(port: 5173, process: 'node'),
      ]);
      expect(probe.scans, 1);
    });

    test('ports a tool of the workspace uses are left out (D12)', () async {
      await c.read(terminalTabsProvider.notifier).openTab();
      local.replace(local.summary(local.summaries.single.id, ports: [5173]));
      c
          .read(toolRegistryProvider.notifier)
          .add(ws: kDefaultWorkspaceId, name: 'x', url: 'localhost:5173');
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, isEmpty);
    });

    test('an SSH pane\'s ports are the server\'s: never suggested', () async {
      await c
          .read(terminalTabsProvider.notifier)
          .openTab(launch: SshLaunch(SshTarget.parseKey('me@host')!));
      local.replace(
        local.summary(
          local.summaries.single.id,
          ports: [5173],
          remote: SessionRemote(
            launch: SshLaunch(SshTarget.parseKey('me@host')!),
          ),
        ),
      );
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, isEmpty);
      expect(probe.scans, 0, reason: 'nothing to look up');
    });

    test('an exited pane\'s ports are not suggested, a live pane\'s are '
        '(R13)', () async {
      final tabs = c.read(terminalTabsProvider.notifier);
      await tabs.openTab();
      await tabs.openTab();
      final [gone, live] = [for (final s in local.summaries) s.id];
      // 8080 is nginx's and 5173 node's in the probe: a suggestion for 8080
      // would show.
      local.replace(local.summary(gone, ports: [8080]));
      local.replace(local.summary(live, ports: [5173]));
      local.views[gone]!.end(2);
      await pumpEventQueue();
      final pane = c
          .read(terminalTabsProvider)
          .tabOfSession(gone)!
          .panes[gone]!;
      expect(pane.exited, isTrue);
      expect(pane.ports, [8080], reason: 'the last ports stay after an exit');
      final list = await c.read(
        toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
      );
      expect(list, const [ToolPortSuggestion(port: 5173, process: 'node')]);
    });

    /// A terminal pane on 3000 and 5173, and an AI agent (pid 900) whose
    /// server on 4000 a working scan would find.
    Future<void> panesAndAnAgent() async {
      await c.read(terminalTabsProvider.notifier).openTab();
      local.replace(
        local.summary(local.summaries.single.id, ports: [3000, 5173]),
      );
      final ai = openTestAiTab(c, title: 'x', cwd: '/w');
      c.read(aiAgentPidsProvider).set(ai.ai!.id, 900);
    }

    /// The suggestions of the default workspace, and every line `debugPrint`
    /// wrote while they were made.
    Future<({List<ToolPortSuggestion> list, List<String> logged})>
    suggestAndLog() async {
      final logged = <String>[];
      final saved = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
      try {
        final list = await c.read(
          toolPortSuggestionsProvider(kDefaultWorkspaceId).future,
        );
        return (list: list, logged: logged);
      } finally {
        debugPrint = saved;
      }
    }

    test(
      'a scan that fails leaves the panes\' ports, without names or the '
      'agent\'s server, and logs only the error\'s type (D12, D24)',
      () async {
        await panesAndAnAgent();
        // What a real failure could carry: ports, a path, a program's name.
        probe.listeningError = const PortProbeException(
          'lsof: 3000,5173 of node in /Users/me/secret',
        );
        final (:list, :logged) = await suggestAndLog();
        expect(list, const [
          ToolPortSuggestion(port: 3000),
          ToolPortSuggestion(port: 5173),
        ]);
        expect(logged, ['tool suggestions: scan failed (PortProbeException)']);
        expect(probe.scans, 1);
      },
    );

    test(
      'a table read that fails after the ports were read costs the '
      'names, not the ports; any error is logged by its type (D12, D24)',
      () async {
        await panesAndAnAgent();
        probe.tableError = StateError('ps said 3000 node /Users/me/secret');
        final (:list, :logged) = await suggestAndLog();
        expect(list, const [
          ToolPortSuggestion(port: 3000),
          ToolPortSuggestion(port: 5173),
        ]);
        expect(logged, ['tool suggestions: scan failed (StateError)']);
      },
    );

    test('a workspace is suggested its own terminals (an AI tab\'s too) and '
        'its own agents\' servers, never another workspace\'s (D12)', () async {
      final tabs = c.read(terminalTabsProvider.notifier);
      final other = c
          .read(sidebarWorkspacesProvider.notifier)
          .createFor(name: 'Other');
      // The default workspace: a terminal tab on 5173, and an AI tab whose
      // agent (900) started a server on 4000 and which has a terminal pane
      // on 6006.
      await tabs.openTab();
      final termA = local.summaries.single.id;
      local.replace(local.summary(termA, ports: [5173]));
      final aiA = openTestAiTab(c, title: 'a', cwd: '/w');
      c.read(aiAgentPidsProvider).set(aiA.ai!.id, 900);
      final paneA = await tabs.addAiTerminal(aiA.id);
      probe.ports[60] = {6006};
      probe.rows[60] = (parent: 1, name: 'storybook');
      local.replace(local.summary(paneA, ports: [6006]));
      // "Other": a terminal tab on 3000, and an AI tab whose agent (910)
      // started a server on 4100.
      final termB = await tabs.openTabFor(cwd: '/w', workspace: other);
      probe.ports[30] = {3000};
      probe.rows[30] = (parent: 1, name: 'python');
      local.replace(local.summary(termB, ports: [3000]));
      final aiB = openTestAiTab(c, title: 'b', cwd: '/w', workspace: other);
      c.read(aiAgentPidsProvider).set(aiB.ai!.id, 910);
      probe.ports[913] = {4100};
      probe.rows[910] = (parent: 1, name: 'claude');
      probe.rows[913] = (parent: 910, name: 'deno');

      final sidebar = c.read(sidebarWorkspacesProvider);
      expect(
        sidebar.tabsOf(kDefaultWorkspaceId),
        unorderedEquals([termA, aiA.id]),
      );
      expect(sidebar.tabsOf(other), unorderedEquals([termB, aiB.id]));
      // As text: a suggestion prints as `ToolPortSuggestion(…)` (D24), which
      // would not say which port leaked.
      Future<String> suggested(String ws) async => [
        for (final s in await c.read(toolPortSuggestionsProvider(ws).future))
          '${s.port} ${s.process}',
      ].join(', ');
      expect(
        await suggested(kDefaultWorkspaceId),
        '4000 node, 5173 node, 6006 storybook',
      );
      expect(await suggested(other), '3000 python, 4100 deno');
    });
  });

  test('recordingAgentPids keeps the pid while the agent runs', () async {
    final pids = AiAgentPids();
    final channel = _Channel();
    final launch = recordingAgentPids(
      (command, {required cwd}) async => channel,
      pids,
      -1,
      pidOf: (_) => 4242,
    );
    await launch(const AgentCommand(executable: 'x'), cwd: '/');
    expect(pids.of(-1), 4242);
    channel.end();
    await Future<void>.delayed(Duration.zero);
    expect(pids.of(-1), isNull);
    expect(pids.toString(), 'AiAgentPids(0)');
  });

  test('a real agent process has its pid read', () async {
    final pids = AiAgentPids();
    final launch = recordingAgentPids(
      (command, {required cwd}) => AgentProcess.start(command, cwd: cwd),
      pids,
      -3,
    );
    final channel = await launch(
      const AgentCommand(executable: '/bin/cat'),
      cwd: Directory.systemTemp.path,
    );
    expect(pids.of(-3), isNotNull);
    await channel.kill();
    await channel.exitCode;
    await Future<void>.delayed(Duration.zero);
    expect(pids.of(-3), isNull);
  }, testOn: '!windows');

  test('the default factory keeps the pid of the agent it launches for a '
      'pane until that agent exits (R12, D12)', () async {
    final tmp = Directory.systemTemp.createTempSync('tool_ports_agent');
    addTearDown(() => tmp.deleteSync(recursive: true));
    // The app's own AiHost, with nothing of the machine in it: the
    // environment is a given map (no login shell), git is never found, the
    // process table is not read. The "agent" is a shell that reads its stdin
    // until the runtime closes it.
    final host = AiHost(
      supportDir: tmp.path,
      clientVersion: 'test',
      env: LoginShellEnv(
        processEnv: const {'PATH': '/usr/bin:/bin'},
        run: (_, _, _, _) async => throw StateError('no login shell here'),
      ),
      checkpoints: CheckpointStores(
        root: '${tmp.path}/ai/checkpoints',
        locator: GitLocator(probe: (_, _, {environment}) async => null),
      ),
      processTable: ({limit, after}) async => null,
    );
    final c = ProviderContainer.test(
      overrides: [aiHostProvider.overrideWithValue(host)],
    );
    const agent = AgentSpec(
      id: 'stand-in',
      name: 'Stand-in',
      launch: CustomLaunch(command: '/bin/sh', args: ['-c', 'cat > /dev/null']),
    );
    final pids = c.read(aiAgentPidsProvider);
    final runtime = c.read(aiRuntimeFactoryProvider)(
      AiRuntimeRequest(agent: agent, cwd: tmp.path, paneId: -7),
    );
    int? pid;
    addTearDown(() async {
      await runtime.dispose();
      // Only the process this test started, if it is somehow still there.
      final started = pid;
      if (started != null && _alive(started)) {
        Process.killPid(started, ProcessSignal.sigkill);
      }
    });

    unawaited(runtime.start());
    expect(
      await _until(() => pids.of(-7) != null),
      isTrue,
      reason: 'the launched agent\'s pid is kept for its pane',
    );
    pid = pids.of(-7)!;
    expect(_alive(pid), isTrue);
    expect(pids.of(-8), isNull, reason: 'only for that pane');

    await runtime.dispose();
    expect(
      await _until(() => pids.of(-7) == null),
      isTrue,
      reason: 'cleared when the agent exits',
    );
    expect(_alive(pid), isFalse, reason: 'the stand-in agent ended');
  }, testOn: '!windows');

  test('clear leaves the pid of a newer agent of the pane, and the pids of '
      'other panes, in place', () {
    final pids = AiAgentPids()
      ..set(-1, 100)
      ..set(-2, 100)
      ..set(-1, 200);
    pids.clear(-1, 100);
    expect(pids.of(-1), 200, reason: 'a newer agent of the pane stays');
    expect(pids.of(-2), 100, reason: 'another pane keeps its own');
    pids.clear(-1, 200);
    expect(pids.of(-1), isNull);
    expect(pids.toString(), 'AiAgentPids(1)');
  });

  test(
    'a restarted agent keeps its pid when the one before it exits late',
    () async {
      final pids = AiAgentPids();
      final older = _Channel();
      final newer = _Channel();
      final launched = [older, newer];
      final pidOfChannel = <AgentChannel, int>{older: 11, newer: 22};
      final launch = recordingAgentPids(
        (command, {required cwd}) async => launched.removeAt(0),
        pids,
        -2,
        pidOf: (channel) => pidOfChannel[channel],
      );
      await launch(const AgentCommand(executable: 'x'), cwd: '/');
      await launch(const AgentCommand(executable: 'x'), cwd: '/');
      expect(pids.of(-2), 22, reason: 'the restart replaced the pid');
      older.end();
      await Future<void>.delayed(Duration.zero);
      expect(
        pids.of(-2),
        22,
        reason: 'the older agent\'s exit is not the newer\'s',
      );
      newer.end();
      await Future<void>.delayed(Duration.zero);
      expect(pids.of(-2), isNull);
    },
  );

  test('runtimeFor passes its pane to the factory, which keeps the agent\'s '
      'pid for that pane (D12)', () {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = cliContainer(FakeLocalSessions(), overrides: fakes.overrides);
    final ai = openTestAiTab(c, cwd: testAiCwd);
    final runtime = c.read(aiRuntimesProvider.notifier).runtimeFor(ai.ai!.id);
    expect(runtime, isNotNull);
    expect(fakes.requests.single.paneId, ai.ai!.id);
  });

  // AiRuntimes.runtimeFor always passes the pane, so aiRuntimeFactoryProvider
  // builds every desktop AI pane's runtime from its own copy of
  // AiHost.runtime, and `host.runtime(...)` is not reached. A change of the
  // original must not go unseen.
  test('AiHost.runtime is still the text the factory\'s copy was made from '
      '(R12)', () {
    // The tests run in apps/desktop; "/" works in a URI on Windows too.
    final source = File.fromUri(
      Directory.current.uri.resolve(
        '../../packages/shellx_ai/lib/src/host/ai_host.dart',
      ),
    );
    expect(
      source.existsSync(),
      isTrue,
      reason: 'read from apps/desktop: ${source.path}',
    );
    expect(
      _hostRuntimeIn(source.readAsStringSync()) ?? 'AiHost.runtime not found',
      _squash(_pinnedHostRuntime),
      reason: _hostRuntimeChanged,
    );
  });
}

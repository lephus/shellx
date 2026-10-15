import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/tools/tool_ports.dart';
import 'package:shellx_desktop/src/tools/tool_registry.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

final class _Probe implements PortProbe, ProcessTableProbe {
  _Probe(this.ports, this.rows);
  final Map<int, Set<int>> ports;
  final Map<int, ProgramRow> rows;
  int scans = 0;

  @override
  Future<Map<int, Set<int>>> listening() async {
    scans++;
    return ports;
  }

  @override
  Future<Map<int, int>> parents() async => const {};

  @override
  Future<Map<int, ProgramRow>> processTable() async => rows;
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
}

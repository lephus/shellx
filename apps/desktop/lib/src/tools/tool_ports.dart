import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart'
    show
        ListeningScan,
        MacPortProbe,
        PortProbe,
        ProcessTableProbe,
        RootedPort,
        WindowsPortProbe;

import '../ai/ai_runtimes.dart' show AiAgentPids, aiAgentPidsProvider;
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'tool_registry.dart';

/// D12: at most this many suggestions.
const int kMaxToolSuggestions = 8;

/// D12: `localhost:<port> · <process>`.
@immutable
final class ToolPortSuggestion {
  const ToolPortSuggestion({required this.port, this.process = ''});
  final int port;

  /// The listening program's name; '' while unknown.
  final String process;

  String get url => 'http://localhost:$port/';

  @override
  bool operator ==(Object other) =>
      other is ToolPortSuggestion &&
      other.port == port &&
      other.process == process;

  @override
  int get hashCode => Object.hash(port, process);

  @override
  String toString() => 'ToolPortSuggestion(…)';
}

/// D12: the ports [panePorts] of the workspace's terminal panes and the
/// [agentPorts] its AI agents' processes listen on, named by [nameOf], less
/// the ports its tools already use, by port, at most [kMaxToolSuggestions].
List<ToolPortSuggestion> toolPortSuggestions({
  required Set<int> panePorts,
  List<RootedPort> agentPorts = const [],
  String Function(int port)? nameOf,
  required Set<int> usedPorts,
}) {
  final named = <int, String>{
    for (final p in panePorts) p: nameOf?.call(p) ?? '',
    for (final p in agentPorts) p.port: p.name,
  };
  final ports = named.keys.where((p) => !usedPorts.contains(p)).toList()
    ..sort();
  return [
    for (final p in ports.take(kMaxToolSuggestions))
      ToolPortSuggestion(port: p, process: named[p]!),
  ];
}

/// D12 (1): the ports the terminal panes of workspace [ws] listen on — an
/// AI tab's terminal pane too, never an SSH pane's (those are the
/// server's, §12).
Set<int> workspacePanePorts(
  TerminalTabsState tabs,
  SidebarState sidebar,
  String ws,
) {
  final ids = sidebar.tabsOf(ws).toSet();
  return {
    for (final tab in tabs.tabs)
      if (ids.contains(tab.id))
        for (final pane in tab.panes.values)
          if (pane.remote == null && !pane.exited) ...pane.ports,
  };
}

/// D12 (2): the pids of the running agents of [ws]'s AI tabs.
Set<int> workspaceAgentPids(
  TerminalTabsState tabs,
  SidebarState sidebar,
  String ws,
  AiAgentPids pids,
) {
  final ids = sidebar.tabsOf(ws).toSet();
  return {
    for (final tab in tabs.tabs)
      if (ids.contains(tab.id))
        for (final pane in tab.aiPanes.keys) ?pids.of(pane),
  };
}

/// The probes of the on-demand scan; tests make them fakes.
final toolPortProbeProvider =
    Provider<({PortProbe ports, ProcessTableProbe table})>((ref) {
      if (Platform.isWindows) {
        final probe = WindowsPortProbe();
        return (ports: probe, table: probe);
      }
      final probe = MacPortProbe();
      return (ports: probe, table: probe);
    });

/// D12: what "Add tool" suggests for workspace [ws] — read once, when the
/// dialog opens (`autoDispose`: a new dialog scans again), in the window,
/// where the agents run, with or without the background service.
final toolPortSuggestionsProvider = FutureProvider.autoDispose
    .family<List<ToolPortSuggestion>, String>((ref, ws) async {
      final tabs = ref.read(terminalTabsProvider);
      final sidebar = ref.read(sidebarWorkspacesProvider);
      final panePorts = workspacePanePorts(tabs, sidebar, ws);
      final roots = workspaceAgentPids(
        tabs,
        sidebar,
        ws,
        ref.read(aiAgentPidsProvider),
      );
      final used = {
        for (final t in ref.read(toolRegistryProvider.notifier).inWorkspace(ws))
          if (t.isLocal) t.port,
      };
      var scan = ListeningScan.empty;
      if (panePorts.isNotEmpty || roots.isNotEmpty) {
        final probe = ref.read(toolPortProbeProvider);
        try {
          scan = await ListeningScan.read(probe.ports, probe.table);
        } on Object catch (error) {
          // The panes' own ports still show, without names.
          debugPrint('tool suggestions: scan failed (${error.runtimeType})');
        }
      }
      return toolPortSuggestions(
        panePorts: panePorts,
        agentPorts: scan.under(roots),
        nameOf: scan.nameOf,
        usedPorts: used,
      );
    });

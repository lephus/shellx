import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart'
    show SessionLimitException, SpawnFailedException;

import '../cli/ui_command_handler.dart' show uiCommandHandlerProvider;
import '../terminal/agent_status.dart' show AgentKind;
import '../terminal/terminal_tabs.dart';
import 'integration_probe.dart';

/// The probe of the real disk and environment (tests replace it).
final integrationProbeProvider = Provider<IntegrationProbe>((ref) {
  final env = Platform.environment;
  return IntegrationProbe(
    fs: const DiskIntegrationFs(),
    env: env,
    home: env['HOME'] ?? env['USERPROFILE'] ?? '',
    windows: Platform.isWindows,
  );
});

/// What Settings › Agents shows: null until the first look.
final integrationStatusProvider =
    NotifierProvider<
      IntegrationStatusNotifier,
      Map<AgentKind, IntegrationStatus>?
    >(IntegrationStatusNotifier.new);

/// A12 D6, D23: the integration of each agent, read-only, and the one action
/// the page has: open a terminal tab that runs the CLI's own installer. The
/// app never changes an agent's file; the diff and the question are shown by
/// the CLI in that tab, and the answer is typed there.
class IntegrationStatusNotifier
    extends Notifier<Map<AgentKind, IntegrationStatus>?> {
  /// Tabs started from the page; when one closes the status is read again
  /// (the user may have said yes in it).
  final _watching = <int>{};
  var _look = 0;

  @override
  Map<AgentKind, IntegrationStatus>? build() {
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) {
      final open = {for (final t in tabs.tabs) t.id};
      final closed = _watching.where((id) => !open.contains(id)).toList();
      if (closed.isEmpty) return;
      _watching.removeAll(closed);
      unawaited(refresh());
    });
    return null;
  }

  /// Reads the files again. Never throws; a failure leaves what was shown.
  Future<void> refresh() async {
    final mine = ++_look;
    Map<AgentKind, IntegrationStatus> found;
    try {
      found = await ref.read(integrationProbeProvider).probe();
    } on Object catch (error) {
      // Only the kind of error: the rest could be a path.
      debugPrint('integrations: not read (${error.runtimeType})');
      return;
    }
    if (ref.mounted && mine == _look) state = found;
  }

  /// A new local tab, selected, that runs `shellx integrations install` (or
  /// `uninstall`) for [agent], without `--yes`. False when no tab opened.
  Future<bool> runInTerminal(AgentKind agent, {required bool remove}) async {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final int id;
    try {
      id = await tabs.openTabFor(cwd: tabs.newTabCwd(), select: true);
    } on SessionLimitException catch (error) {
      tabs.showNotice(SessionLimitNotice(error.max));
      return false;
    } on SpawnFailedException catch (error) {
      tabs.showNotice(spawnNoticeFor(error));
      return false;
    } on Object catch (error) {
      // Another open in flight, or the shell ended at once.
      debugPrint('integrations: no tab (${error.runtimeType})');
      return false;
    }
    if (!ref.mounted) return false;
    _watching.add(id);
    // The same path as `shellx new-tab --cmd`: waits for the shell.
    ref
        .read(uiCommandHandlerProvider)
        .onCommand
        ?.call(id, integrationCommand(agent, remove: remove));
    return true;
  }
}

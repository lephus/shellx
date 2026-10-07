import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../platform/settings_store.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'remote_tools_provider.dart';
import 'ssh_settings.dart';

final class SshSuggestions {
  const SshSuggestions({required this.config, required this.recent});
  final List<String> config;
  final List<String> recent;
}

final sshActionsProvider = Provider<SshActions>(SshActions.new);

/// The one way in for keys, menus, the dialog, the tray and the CLI (A8).
final class SshActions {
  SshActions(this._ref);
  final Ref _ref;

  SettingsStore get _settings => _ref.read(settingsStoreProvider);
  SidebarWorkspaces get _side => _ref.read(sidebarWorkspacesProvider.notifier);
  TerminalTabs get _tabs => _ref.read(terminalTabsProvider.notifier);
  RemoteTools get _tools => _ref.read(remoteToolsProvider);

  bool hookFor(String key) => sshHookFor(_settings, key);

  /// Opens [launch] in [host]'s workspace (made on first use); a workspace
  /// made now whose tab never came (a toast says why) is taken back.
  Future<void> _openOnHost(SshTarget host, SessionLaunch launch) async {
    final existing = _side.workspaceForHost(host.key);
    final workspace = existing ?? _side.createForHost(host);
    await _side.openTabIn(workspace, launch: launch);
    if (existing == null) _side.discard(workspace);
  }

  /// ⌘T, sidebar `+` (D23).
  Future<void> newTab() async {
    final side = _ref.read(sidebarWorkspacesProvider);
    if (side.workspace(side.currentId)?.ssh != null) {
      return _side.openTabIn(side.currentId);
    }
    return _tabs.openTab();
  }

  /// The dialog's Connect (D23, D42). [noHook] is the box's value when the
  /// user could see it (null: leave the per-server setting alone).
  Future<void> connect(
    SshTarget target, {
    String? remoteCwd,
    bool? noHook,
  }) async {
    if (noHook != null) {
      await setPlainTarget(_settings, target.key, plain: noHook);
    }
    await rememberTarget(_settings, target);
    await _openOnHost(
      target,
      SshLaunch(target, remoteCwd: remoteCwd, hook: hookFor(target.key)),
    );
  }

  /// A7 `shellx ssh` (D33): no focus change unless [select]. Throws what
  /// `openTabFor` throws.
  Future<int> connectForCli(
    SshTarget target, {
    String? workspaceId,
    String? remoteCwd,
    bool hook = true,
    bool select = false,
  }) async {
    final existing = workspaceId ?? _side.workspaceForHost(target.key);
    final workspace =
        existing ?? _side.createForHost(target, makeCurrent: select);
    final int tab;
    try {
      tab = await _tabs.openTabFor(
        launch: SshLaunch(
          target,
          remoteCwd: remoteCwd,
          hook: hook && hookFor(target.key),
        ),
        select: select,
        workspace: workspace,
      );
    } catch (_) {
      // A workspace always has a tab (A2): take back the one made for this.
      if (existing == null) _side.discard(workspace);
      rethrow;
    }
    await rememberTarget(_settings, target);
    return tab;
  }

  /// D25: here, or on [host] without ever prompting.
  Future<TmuxListResult> listTmux(SshTarget? host) async {
    if (host == null) {
      final tmux = _tools.tmuxPath;
      if (tmux == null) return const TmuxUnavailable();
      final run = _ref.read(commandRunnerProvider);
      final r = await run(tmux, [
        'list-sessions',
        '-F',
        tmuxListFormat,
      ], timeout: const Duration(seconds: 5));
      return classifyTmuxList(r, remote: false);
    }
    final control = _tools.control;
    if (control == null) return const TmuxListFailed(TmuxListFailure.other);
    final r = await control.runRemote(
      host,
      remoteTmuxListScript(),
      timeout: const Duration(seconds: 5),
    );
    return classifyTmuxList(r, remote: true);
  }

  TmuxLaunch _tmuxLaunch(String name, SshTarget? host, bool create) =>
      TmuxLaunch(
        name,
        host: host,
        create: create,
        hook: host == null || hookFor(host.key),
      );

  /// D26: a server's session goes to its workspace; a local one to the
  /// current workspace.
  Future<void> attachTmux(
    String name, {
    SshTarget? host,
    bool create = false,
  }) async {
    final launch = _tmuxLaunch(name, host, create);
    if (host == null) return _tabs.openTab(launch: launch);
    await rememberTarget(_settings, host);
    await _openOnHost(host, launch);
  }

  Future<int> attachTmuxForCli(
    String name, {
    SshTarget? host,
    bool create = false,
    bool select = false,
  }) async {
    final target = host == null ? null : _workspaceForCli(host, select);
    final int tab;
    try {
      tab = await _tabs.openTabFor(
        launch: _tmuxLaunch(name, host, create),
        select: select,
        workspace: target?.$1,
      );
    } catch (_) {
      if (target != null && target.$2) _side.discard(target.$1);
      rethrow;
    }
    return tab;
  }

  /// A server's workspace for the command line, and whether it was made now.
  (String, bool) _workspaceForCli(SshTarget host, bool select) {
    final existing = _side.workspaceForHost(host.key);
    if (existing != null) return (existing, false);
    return (_side.createForHost(host, makeCurrent: select), true);
  }

  /// D6: config names, then recent ones not already listed.
  Future<SshSuggestions> suggestions() async {
    final config = await _ref.read(sshConfigHostsProvider)();
    final recent = [
      for (final t in recentTargets(_settings))
        if (!config.contains(t.key)) t.key,
    ];
    return SshSuggestions(config: config, recent: recent);
  }

  Future<void> clearRecent() => clearRecentTargets(_settings);
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../terminal/local_sessions_provider.dart';
import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import 'agent_marks.dart';
import 'cli_fields.dart';
import 'cli_targets.dart';
import 'ui_pane_io.dart';

/// How a request learns its client left: [Future] completes then; the
/// function tells at once (A7 D21, D33).
typedef _Leaving = (Future<void>?, bool Function()?);

final uiCommandHandlerProvider = Provider<UiCommandHandler>(
  (ref) => UiCommandHandler(ref),
);

const _runningCommand = CliFailure(
  CliError.runningCommand,
  'a command is running; use --force',
);

/// A7 §3.3: the `ui.*` requests of the command line, run on the window's
/// tabs and sidebar. Browser panes (A6) are not here yet: `ls` lists
/// terminal panes only and `ui.browser.*` is `unknown_type`.
///
/// Never logs request contents (cwd, commands, names, text sent or read).
final class UiCommandHandler implements UiApi {
  UiCommandHandler(this._ref, {this.openWait = const Duration(seconds: 10)})
    : _io = PaneIoCommands(_ref) {
    onCommand = _io.typeCommand;
  }

  final Ref _ref;

  /// D16, D19-D21: send, read, wait and `--cmd`.
  final PaneIoCommands _io;

  /// D33: how long a request waits for another open in flight.
  final Duration openWait;

  /// D16 (`CommandInjector`): types `--cmd` once the new shell is ready.
  void Function(int pane, String cmd)? onCommand;

  /// D17 `--raise`: shows and activates the window (A1 D11); set by the
  /// window (Task 9).
  Future<void> Function()? onRaise;

  TerminalTabs get _tabs => _ref.read(terminalTabsProvider.notifier);
  TerminalTabsState get _tabsState => _ref.read(terminalTabsProvider);
  SidebarWorkspaces get _side => _ref.read(sidebarWorkspacesProvider.notifier);
  SidebarState get _sideState => _ref.read(sidebarWorkspacesProvider);
  AgentMarks get _marks => _ref.read(agentMarksProvider.notifier);

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) async {
    final t = request.type;
    return switch (t) {
      CliType.uiLs => _ls(),
      CliType.uiTabNew => _tabNew(request, (cancelled, isGone)),
      CliType.uiTabRename => _tabRename(request),
      CliType.uiPaneSplit => _split(request, (cancelled, isGone)),
      CliType.uiFocus => _focus(request),
      CliType.uiClose => _close(request),
      CliType.uiWorkspaceNew => _workspaceNew(request, (cancelled, isGone)),
      CliType.uiWorkspaceRename => _workspaceRename(request),
      CliType.uiWorkspaceMove => _workspaceMove(request),
      CliType.uiPaneSend => _io.send(request),
      CliType.uiPaneRead => _io.read(request),
      CliType.uiPaneWait => _io.wait(request, cancelled),
      // Task 8: ui.notify, events.
      // ui.browser.*: pending A6.
      _ => throw CliFailure(MuxError.unknownType, 'unknown request $t'),
    };
  }

  /// D33: retries while another open is in flight (every 50 ms, up to
  /// [openWait]); maps the tab list's failures to wire codes. Once the
  /// client is gone ([leaving]) it stops waiting and never opens
  /// (`cancelled`). [open] runs afresh on every try (what it resolves may
  /// have changed).
  Future<T> _opening<T>(Future<T> Function() open, _Leaving leaving) async {
    final (cancelled, isGone) = leaving;
    var gone = false;
    final left = cancelled?.then<void>(
      (_) => gone = true,
      onError: (Object _) => gone = true,
    );
    final waited = Stopwatch()..start();
    while (true) {
      if (gone || (isGone?.call() ?? false)) {
        throw const CliFailure(CliError.cancelled, 'the client left');
      }
      try {
        return await open();
      } on OpenBusyException {
        if (waited.elapsed >= openWait) {
          throw const CliFailure(
            MuxError.busy,
            'ShellX is opening another shell; try again',
          );
        }
        await Future.any([
          Future<void>.delayed(const Duration(milliseconds: 50)),
          ?left,
        ]);
      } on PaneNoRoomException {
        throw const CliFailure(
          CliError.noRoom,
          'not enough room to split this pane',
        );
      } on PaneGoneException {
        throw const CliFailure(MuxError.notFound, 'the pane ended');
      } on SessionLimitException catch (e) {
        throw CliFailure(
          MuxError.sessionLimit,
          'ShellX already has ${e.max} shells',
        );
      } on SpawnFailedException {
        // The message may hold a path: not passed on.
        throw const CliFailure(
          MuxError.spawnFailed,
          'the shell could not start',
        );
      }
    }
  }

  // ---- ls (D13) -----------------------------------------------------------

  Future<Map<String, Object?>> _ls() async {
    final tabs = _tabsState;
    final side = _sideState;
    final unread = _ref.read(tabAttentionProvider).unread;
    final marks = _ref.read(agentMarksProvider);
    final now = _ref.read(agentMarksClockProvider)();
    final byId = {for (final t in tabs.tabs) t.id: t};

    Map<String, Object?> pane(TerminalTab tab, PaneSession p) => {
      'id': p.id,
      'kind': 'terminal',
      'title': p.automaticLabel,
      'cwd': p.cwd,
      'branch': p.gitBranch,
      'ports': p.ports,
      'running': !p.exited && p.runningCommand,
      'exited': p.exited,
      'exitCode': p.exitCode,
      'focused': p.id == tab.focusedPaneId,
      'zoomed': p.id == tab.zoomedPaneId,
      'phone': p.phoneAttached,
      'driver': p.driver.name,
      'agent': marks.paneActive(p.id, now),
    };

    Map<String, Object?> tab(TerminalTab tab) => {
      'id': tab.id,
      'title': tab.label,
      'custom': tab.customTitle != null,
      'selected': tab.id == tabs.selectedId,
      'unread': unread[tab.id]?.count ?? 0,
      'running': _tabs.runningPaneCount(tab.id) > 0,
      'agent': marks.tabActive(tab.id, now),
      'panes': [
        for (final id in tab.paneOrder)
          if (tab.panes[id] case final p?) pane(tab, p),
      ],
    };

    return {
      'workspaces': [
        for (final w in side.workspaces)
          {
            'id': w.id,
            'name': _side.displayName(w.id),
            'current': w.id == side.currentId,
            'collapsed': w.collapsed,
            'tabs': [
              for (final id in side.tabsOf(w.id))
                if (byId[id] case final t?) tab(t),
            ],
          },
      ],
      'selectedTab': tabs.selectedId,
      'focusedPane': tabs.selected?.focusedPaneId,
    };
  }

  // ---- tabs and panes -----------------------------------------------------

  /// D14: in [workspace] (default: the current one), not selected unless
  /// `focus`.
  /// The workspace is resolved on every try: one deleted during the D33
  /// wait is `not_found`, and nothing opens.
  Future<Map<String, Object?>> _tabNew(MuxMessage r, _Leaving leaving) async {
    final wsKey = stringField(r, 'workspace');
    final cwd = stringField(r, 'cwd');
    final cmd = textField(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final select = flagField(r, 'focus');
    final tab = await _opening(
      () => _tabs.openTabFor(
        cwd: cwd,
        select: select,
        workspace: wsKey == null
            ? null
            : resolveWorkspace(_sideState, wsKey, _side.displayName),
      ),
      leaving,
    );
    if (select) _side.reveal(tab);
    _marks.touch(tab: tab, pane: tab);
    if (cmd != null) onCommand?.call(tab, cmd);
    return {'tab': tab, 'pane': tab};
  }

  /// D15: any pane of any tab; focus and selection stay unless `focus`,
  /// which then focuses the new pane and selects its tab (as `ui.focus`).
  Future<Map<String, Object?>> _split(MuxMessage r, _Leaving leaving) async {
    final target = resolvePane(_tabsState, parseTarget(r.fields['pane'], null));
    final axis = switch (r.fields['direction'] ?? 'right') {
      'right' => SplitAxis.row,
      'down' => SplitAxis.column,
      _ => throw badRequest('direction is right or down'),
    };
    final cwd = stringField(r, 'cwd');
    final cmd = textField(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final focus = flagField(r, 'focus');
    final pane = await _opening(
      () => _tabs.splitPaneFor(target, axis, cwd: cwd, focus: focus),
      leaving,
    );
    final tab = _tabsState.tabOfSession(pane)!.id;
    if (focus) {
      _tabs.focusPane(pane);
      _side.reveal(tab);
    }
    _marks.touch(tab: tab, pane: pane);
    if (cmd != null) onCommand?.call(pane, cmd);
    return {'pane': pane, 'tab': tab};
  }

  /// D17: a tab is selected (its workspace expands); a pane also gets the
  /// focus. The window comes forward only with `raise`.
  Future<Map<String, Object?>> _focus(MuxMessage r) async {
    final target = parseTarget(r.fields['pane'], r.fields['tab']);
    final raise = flagField(r, 'raise');
    final s = _tabsState;
    final tab = resolveTab(s, target);
    final pane = target is TabRef ? null : resolvePane(s, target);
    _tabs.select(tab);
    if (pane != null) _tabs.focusPane(pane);
    _side.reveal(tab);
    _marks.touch(tab: tab, pane: pane);
    if (raise) await onRaise?.call();
    return const {};
  }

  /// D18: a running command needs `force`; no dialog opens on the window.
  /// The Agent mark goes on what is left: nothing for a closed tab, the
  /// tab for a closed pane (unless it was the last).
  Future<Map<String, Object?>> _close(MuxMessage r) async {
    final target = parseTarget(r.fields['pane'], r.fields['tab']);
    final force = flagField(r, 'force');
    final s = _tabsState;
    if (target is TabRef) {
      final tab = resolveTab(s, target);
      if (!force && _tabs.needsCloseConfirm(tab)) throw _runningCommand;
      _tabs.close(tab);
      return const {};
    }
    final pane = resolvePane(s, target);
    if (!force && _tabs.needsPaneCloseConfirm(pane)) throw _runningCommand;
    final tab = s.tabOfSession(pane)!.id;
    _tabs.closePane(pane);
    if (_tabsState.tabs.any((t) => t.id == tab)) _marks.touch(tab: tab);
    return const {};
  }

  /// D22 (A2 D19): trimmed, at most 64 characters; blank → automatic.
  Future<Map<String, Object?>> _tabRename(MuxMessage r) async {
    final tab = resolveTab(_tabsState, parseTarget(null, r.fields['tab']));
    _tabs.rename(tab, stringField(r, 'name', max: 1024) ?? '');
    _marks.touch(tab: tab);
    return const {};
  }

  // ---- workspaces (D22) ---------------------------------------------------

  /// A new workspace always has a tab (A2): the tab opens straight into it
  /// (never through the current workspace); when it cannot open, the
  /// empty workspace goes again, silently. The current workspace and the
  /// selection stay unless `focus`; no name field opens.
  Future<Map<String, Object?>> _workspaceNew(
    MuxMessage r,
    _Leaving leaving,
  ) async {
    final name = stringField(r, 'name', max: 1024);
    final focus = flagField(r, 'focus');
    final ws = _side.createFor(name: name);
    final int tab;
    try {
      tab = await _opening(
        () => _tabs.openTabFor(select: focus, workspace: ws),
        leaving,
      );
    } on Object {
      _side.discard(ws); // a workspace always has a tab (A2)
      rethrow;
    }
    _marks.touch(tab: tab, pane: tab);
    // Where the tab really is: [ws] may have gone during the D33 wait.
    return {'workspace': _sideState.workspaceOf(tab) ?? ws, 'tab': tab};
  }

  Future<Map<String, Object?>> _workspaceRename(MuxMessage r) async {
    final key =
        stringField(r, 'workspace') ??
        (throw badRequest('workspace is needed'));
    final name = stringField(r, 'name', max: 1024) ?? '';
    final ws = resolveWorkspace(_sideState, key, _side.displayName);
    if (name.trim().isEmpty) {
      throw badRequest('a workspace name cannot be blank');
    }
    _side.rename(ws, name);
    return const {};
  }

  /// To the end of the workspace.
  Future<Map<String, Object?>> _workspaceMove(MuxMessage r) async {
    final tab = resolveTab(_tabsState, parseTarget(null, r.fields['tab']));
    final key =
        stringField(r, 'workspace') ??
        (throw badRequest('workspace is needed'));
    _side.moveTab(tab, resolveWorkspace(_sideState, key, _side.displayName));
    _marks.touch(tab: tab);
    return const {};
  }

  // ---- completed in Task 8 ------------------------------------------------

  @override
  Stream<Map<String, Object?>> events() => const Stream.empty();

  @override
  Future<void> notifyApp({String? title, required String body}) async {}

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      _ref.read(localSessionsProvider).notify(pane, title: title, body: body);
}

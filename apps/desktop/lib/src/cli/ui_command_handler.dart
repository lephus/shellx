import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:xterm/xterm.dart';

import '../terminal/desktop_terminal.dart';
import '../terminal/local_sessions_provider.dart';
import '../terminal/pane_layout.dart';
import '../terminal/sidebar_workspaces.dart';
import '../terminal/tab_attention.dart';
import '../terminal/terminal_tabs.dart';
import 'agent_marks.dart';
import 'cli_targets.dart';
import 'pane_text.dart';
import 'pane_waiter.dart';

final uiCommandHandlerProvider = Provider<UiCommandHandler>(
  (ref) => UiCommandHandler(ref),
);

CliFailure _bad(String message) => CliFailure(MuxError.badRequest, message);

const _runningCommand = CliFailure(
  CliError.runningCommand,
  'a command is running; use --force',
);

/// A7 D32: a text field of a request (`send` text) is at most this much
/// UTF-8.
const kSendMaxBytes = 49152;

/// A7 D16: `--cmd` is at most this much UTF-8.
const kCmdMaxBytes = 16384;

/// A7 D21: a `wait --match` pattern is at most this much UTF-8.
const kPatternMaxBytes = 1024;

/// A7 §3.3: the `ui.*` requests of the command line, run on the window's
/// tabs and sidebar. Browser panes (A6) are not here yet: `ls` lists
/// terminal panes only and `ui.browser.*` is `unknown_type`.
///
/// Never logs request contents (cwd, commands, names, text sent or read).
final class UiCommandHandler implements UiApi {
  UiCommandHandler(this._ref, {this.openWait = const Duration(seconds: 10)}) {
    final injector = CommandInjector(_probe, (pane, text) {
      try {
        _send(pane, text: text, enter: true);
      } on CliFailure {
        // The pane ended before its shell was ready: nothing to type into.
      }
    });
    onCommand = (pane, cmd) {
      try {
        injector.inject(pane, cmd);
      } on CliFailure {
        // The pane is already gone.
      }
    };
  }

  final Ref _ref;

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
  }) async {
    final t = request.type;
    return switch (t) {
      CliType.uiLs => _ls(),
      CliType.uiTabNew => _tabNew(request, cancelled),
      CliType.uiTabRename => _tabRename(request),
      CliType.uiPaneSplit => _split(request, cancelled),
      CliType.uiFocus => _focus(request),
      CliType.uiClose => _close(request),
      CliType.uiWorkspaceNew => _workspaceNew(request, cancelled),
      CliType.uiWorkspaceRename => _workspaceRename(request),
      CliType.uiWorkspaceMove => _workspaceMove(request),
      CliType.uiPaneSend => _sendRequest(request),
      CliType.uiPaneRead => _read(request),
      CliType.uiPaneWait => _wait(request, cancelled),
      // Task 8: ui.notify, events.
      // ui.browser.*: pending A6.
      _ => throw CliFailure(MuxError.unknownType, 'unknown request $t'),
    };
  }

  // ---- fields -------------------------------------------------------------

  String? _string(MuxMessage r, String key, {int max = 4096}) {
    final v = r.fields[key];
    if (v == null) return null;
    if (v is! String || v.length > max) {
      throw _bad('$key must be text of at most $max characters');
    }
    return v;
  }

  /// D32: text of at most [maxBytes] of UTF-8 ([limit] says it in KiB).
  String? _text(
    MuxMessage r,
    String key, {
    required int maxBytes,
    required String limit,
  }) {
    final v = r.fields[key];
    if (v == null) return null;
    if (v is! String) throw _bad('$key must be text');
    if (v.length > maxBytes || utf8.encode(v).length > maxBytes) {
      throw _bad('$key is over $limit');
    }
    return v;
  }

  bool _flag(MuxMessage r, String key) {
    final v = r.fields[key];
    if (v == null) return false;
    if (v is! bool) throw _bad('$key must be true or false');
    return v;
  }

  /// D33: retries while another open is in flight (every 50 ms, up to
  /// [openWait]); maps the tab list's failures to wire codes. Once the
  /// client is gone ([cancelled]) it stops waiting and never opens.
  /// [open] runs afresh on every try (what it resolves may have changed).
  Future<T> _opening<T>(
    Future<T> Function() open,
    Future<void>? cancelled,
  ) async {
    var gone = false;
    final left = cancelled?.then<void>(
      (_) => gone = true,
      onError: (Object _) => gone = true,
    );
    // A client already gone: its [left] callback is queued before this
    // turn and runs first, so nothing opens for it.
    if (left != null) await Future<void>.value();
    final waited = Stopwatch()..start();
    while (true) {
      if (gone) throw const CliFailure(MuxError.busy, 'the client left');
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
  Future<Map<String, Object?>> _tabNew(
    MuxMessage r,
    Future<void>? cancelled,
  ) async {
    final wsKey = _string(r, 'workspace');
    final cwd = _string(r, 'cwd');
    final cmd = _text(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final select = _flag(r, 'focus');
    final tab = await _opening(
      () => _tabs.openTabFor(
        cwd: cwd,
        select: select,
        workspace: wsKey == null
            ? null
            : resolveWorkspace(_sideState, wsKey, _side.displayName),
      ),
      cancelled,
    );
    if (select) _side.reveal(tab);
    _marks.touch(tab: tab, pane: tab);
    if (cmd != null) onCommand?.call(tab, cmd);
    return {'tab': tab, 'pane': tab};
  }

  /// D15: any pane of any tab; focus and selection stay unless `focus`,
  /// which then focuses the new pane and selects its tab (as `ui.focus`).
  Future<Map<String, Object?>> _split(
    MuxMessage r,
    Future<void>? cancelled,
  ) async {
    final target = resolvePane(_tabsState, parseTarget(r.fields['pane'], null));
    final axis = switch (r.fields['direction'] ?? 'right') {
      'right' => SplitAxis.row,
      'down' => SplitAxis.column,
      _ => throw _bad('direction is right or down'),
    };
    final cwd = _string(r, 'cwd');
    final cmd = _text(r, 'cmd', maxBytes: kCmdMaxBytes, limit: '16 KiB');
    final focus = _flag(r, 'focus');
    final pane = await _opening(
      () => _tabs.splitPaneFor(target, axis, cwd: cwd, focus: focus),
      cancelled,
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
    final raise = _flag(r, 'raise');
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
    final force = _flag(r, 'force');
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
    _tabs.rename(tab, _string(r, 'name', max: 1024) ?? '');
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
    Future<void>? cancelled,
  ) async {
    final name = _string(r, 'name', max: 1024);
    final focus = _flag(r, 'focus');
    final ws = _side.createFor(name: name);
    final int tab;
    try {
      tab = await _opening(
        () => _tabs.openTabFor(select: focus, workspace: ws),
        cancelled,
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
    final key = _string(r, 'workspace') ?? (throw _bad('workspace is needed'));
    final name = _string(r, 'name', max: 1024) ?? '';
    final ws = resolveWorkspace(_sideState, key, _side.displayName);
    if (name.trim().isEmpty) throw _bad('a workspace name cannot be blank');
    _side.rename(ws, name);
    return const {};
  }

  /// To the end of the workspace.
  Future<Map<String, Object?>> _workspaceMove(MuxMessage r) async {
    final tab = resolveTab(_tabsState, parseTarget(null, r.fields['tab']));
    final key = _string(r, 'workspace') ?? (throw _bad('workspace is needed'));
    _side.moveTab(tab, resolveWorkspace(_sideState, key, _side.displayName));
    _marks.touch(tab: tab);
    return const {};
  }

  // ---- send, read, wait (D19-D21) ----------------------------------------

  /// A terminal pane that exists (exited or not).
  PaneSession _pane(int id) =>
      _tabsState.tabOfSession(id)?.panes[id] ??
      (throw CliFailure(MuxError.notFound, 'no pane p$id'));

  /// D19: a browser pane (negative id, A6) is `bad_request`.
  int _paneArg(MuxMessage r) {
    final raw = r.fields['pane'];
    if (raw is int && raw < 0) {
      throw _bad('p$raw is a browser pane; use shellx browser');
    }
    return resolvePane(_tabsState, parseTarget(raw, null));
  }

  void _touchPane(int pane) =>
      _marks.touch(tab: _tabsState.tabOfSession(pane)!.id, pane: pane);

  Future<Map<String, Object?>> _sendRequest(MuxMessage r) async {
    final pane = _paneArg(r);
    final text = _text(r, 'text', maxBytes: kSendMaxBytes, limit: '48 KiB');
    final rawKeys = r.fields['keys'] ?? const <Object?>[];
    if (rawKeys is! List) throw _bad('keys must be a list of key names');
    final keys = [for (final k in rawKeys) _key(k)];
    final enter = _flag(r, 'enter');
    if ((text == null || text.isEmpty) && keys.isEmpty && !enter) {
      throw _bad('nothing to send');
    }
    _send(pane, text: text, keys: keys, enter: enter);
    return const {};
  }

  /// As the user would type it (the desktop drives, A1 D6): [text] through
  /// the clipboard's paste (controls stripped, bracketed when the shell
  /// asked), then [keys], then Enter.
  void _send(
    int pane, {
    String? text,
    List<void Function(DesktopTerminal)> keys = const [],
    bool enter = false,
  }) {
    final p = _pane(pane);
    if (p.exited) throw const CliFailure(CliError.exited, 'the pane exited');
    final t = p.terminal;
    if (text != null && text.isNotEmpty) t.paste(text);
    for (final k in keys) {
      k(t);
    }
    if (enter) t.keyInput(TerminalKey.enter);
    _touchPane(pane);
  }

  static const _named = <String, TerminalKey>{
    'enter': TerminalKey.enter,
    'tab': TerminalKey.tab,
    'esc': TerminalKey.escape,
    'backspace': TerminalKey.backspace,
    'up': TerminalKey.arrowUp,
    'down': TerminalKey.arrowDown,
    'left': TerminalKey.arrowLeft,
    'right': TerminalKey.arrowRight,
    'home': TerminalKey.home,
    'end': TerminalKey.end,
    'pageup': TerminalKey.pageUp,
    'pagedown': TerminalKey.pageDown,
  };

  static final _ctrlKey = RegExp(r'^ctrl-([a-z\\\]])$');

  /// D19: through `keyInput`/`charInput`, so cursor keys follow the
  /// application's cursor mode.
  void Function(DesktopTerminal) _key(Object? name) {
    if (name is! String) throw _bad('a key is a name');
    final k = _named[name];
    if (k != null) return (t) => t.keyInput(k);
    final ctrl = _ctrlKey.firstMatch(name);
    if (ctrl != null) {
      final ch = ctrl.group(1)!.codeUnitAt(0);
      return (t) => t.charInput(ch, ctrl: true);
    }
    throw _bad(name.length <= 32 ? 'unknown key "$name"' : 'unknown key');
  }

  Future<Map<String, Object?>> _read(MuxMessage r) async {
    final pane = _paneArg(r);
    final lines = r.fields['lines'];
    if (lines != null &&
        (lines is! int || lines < 1 || lines > kReadMaxLines)) {
      throw _bad('lines is 1–$kReadMaxLines');
    }
    final offset = r.fields['offset'] ?? 0;
    if (offset is! int || offset < 0) throw _bad('bad offset');
    final page = readPage(
      _pane(pane).terminal,
      lines: lines as int?,
      ansi: _flag(r, 'ansi'),
      offset: offset,
    );
    _touchPane(pane);
    return {'text': page.text, 'next': ?page.next};
  }

  /// D21: holds the connection until done; ends at once when the client
  /// goes ([cancelled]).
  Future<Map<String, Object?>> _wait(
    MuxMessage r,
    Future<void>? cancelled,
  ) async {
    final pane = _paneArg(r);
    final ms = r.fields['timeoutMs'] ?? 30000;
    if (ms is! int || ms < 1 || ms > 3600000) {
      throw _bad('timeout is 1 ms–3600 s');
    }
    final timeout = Duration(milliseconds: ms);
    final Future<Map<String, Object?>> Function(PaneProbe) start;
    switch (r.fields['mode']) {
      case 'idle':
        final quiet = r.fields['quietMs'] ?? 500;
        if (quiet is! int || quiet < 0 || quiet > 60000) {
          throw _bad('quiet is 0–60000 ms');
        }
        start = (p) => waitIdle(
          p,
          quiet: Duration(milliseconds: quiet),
          timeout: timeout,
          cancelled: cancelled,
        );
      case 'exit':
        start = (p) => waitExit(p, timeout: timeout, cancelled: cancelled);
      case 'match':
        final pattern =
            _text(r, 'pattern', maxBytes: kPatternMaxBytes, limit: '1 KiB') ??
            (throw _bad('pattern is needed'));
        final RegExp re;
        try {
          re = RegExp(pattern, multiLine: true);
        } on FormatException {
          throw _bad('invalid regular expression');
        }
        final fromNow = _flag(r, 'fromNow');
        start = (p) => waitMatch(
          p,
          re,
          fromNow: fromNow,
          timeout: timeout,
          cancelled: cancelled,
        );
      default:
        throw _bad('mode is idle, exit or match');
    }
    _touchPane(pane);
    return start(_probe(pane));
  }

  /// A live view of one pane, for waits and `--cmd`. Throws `not_found`
  /// when the pane is gone.
  PaneProbe _probe(int pane) => _LivePane(_ref, pane, _pane(pane).terminal);

  // ---- completed in Task 8 ------------------------------------------------

  @override
  Stream<Map<String, Object?>> events() => const Stream.empty();

  @override
  Future<void> notifyApp({String? title, required String body}) async {}

  @override
  bool notifyPane(int pane, {String? title, required String body}) =>
      _ref.read(localSessionsProvider).notify(pane, title: title, body: body);
}

final class _LivePane implements PaneProbe {
  _LivePane(this._ref, this.id, this.terminal);
  final Ref _ref;
  final int id;

  /// Kept: an exit with code 0 removes the pane, not what it showed.
  @override
  final Terminal terminal;

  PaneSession? get _p =>
      _ref.read(terminalTabsProvider).tabOfSession(id)?.panes[id];

  @override
  bool get hooked => _p?.cwd != null;
  @override
  bool get running => _p?.runningCommand ?? false;
  @override
  bool get exited => _p?.exited ?? true;

  /// Exit 0 removed the pane (A3 D7): the code the tab list kept.
  @override
  int? get exitCode =>
      _p?.exitCode ?? _ref.read(terminalTabsProvider.notifier).lastExitCode(id);

  @override
  Stream<void> get output => _ref
      .read(terminalTabsProvider.notifier)
      .paneOutputs
      .where((p) => p == id)
      .map((_) {});

  @override
  Stream<void> get changes {
    ProviderSubscription<TerminalTabsState>? sub;
    late final StreamController<void> c;
    c = StreamController<void>(
      sync: true,
      onListen: () =>
          sub = _ref.listen(terminalTabsProvider, (_, _) => c.add(null)),
      onCancel: () => sub?.close(),
    );
    return c.stream;
  }
}

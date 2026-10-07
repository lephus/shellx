import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:xterm/xterm.dart';

import '../terminal/desktop_terminal.dart';
import '../terminal/terminal_tabs.dart';
import 'agent_marks.dart';
import 'cli_fields.dart';
import 'cli_targets.dart';
import 'match_scanner.dart';
import 'pane_text.dart';
import 'pane_waiter.dart';

/// A7 D32: a text field of a request (`send` text) is at most this much
/// UTF-8.
const kSendMaxBytes = 49152;

/// A7 D16: `--cmd` is at most this much UTF-8.
const kCmdMaxBytes = 16384;

/// A7 D21: a `wait --match` pattern is at most this much UTF-8.
const kPatternMaxBytes = 1024;

/// A7 D16, D19-D21: what the command line types into and reads from a
/// terminal pane — `ui.pane.send`, `ui.pane.read`, `ui.pane.wait` and
/// `--cmd`. Never logs text sent or read.
final class PaneIoCommands {
  PaneIoCommands(this._ref) {
    _injector = CommandInjector(_probe, typeNow);
  }

  /// Types [text] and Enter into [pane] now.
  void typeNow(int pane, String text) {
    try {
      _send(pane, text: text, enter: true);
    } on CliFailure {
      // The pane ended before its shell was ready: nothing to type into.
    }
  }

  final Ref _ref;
  late final CommandInjector _injector;

  TerminalTabsState get _tabsState => _ref.read(terminalTabsProvider);
  AgentMarks get _marks => _ref.read(agentMarksProvider.notifier);

  /// D16: types [cmd] into new pane [pane] once its shell is ready.
  void typeCommand(int pane, String cmd) {
    try {
      _injector.inject(pane, cmd);
    } on CliFailure {
      // The pane is already gone.
    }
  }

  /// A8 D22: a pane id from before a reconnect names the new session.
  int _forward(int id) =>
      _ref.read(terminalTabsProvider.notifier).resolveReplaced(id);

  /// A terminal pane that exists (exited or not).
  PaneSession _pane(int id) =>
      _tabsState.tabOfSession(id)?.panes[id] ??
      (throw CliFailure(MuxError.notFound, 'no pane p$id'));

  /// D19: a browser pane (negative id, A6) is `bad_request`.
  int _paneArg(MuxMessage r) {
    final target = parseTarget(r.fields['pane'], null, forward: _forward);
    if (target is PaneRef && target.id < 0) {
      throw badRequest('p${target.id} is a browser pane; use shellx browser');
    }
    return resolvePane(_tabsState, target);
  }

  void _touchPane(int pane) =>
      _marks.touch(tab: _tabsState.tabOfSession(pane)!.id, pane: pane);

  Future<Map<String, Object?>> send(MuxMessage r) async {
    final pane = _paneArg(r);
    final text = textField(r, 'text', maxBytes: kSendMaxBytes, limit: '48 KiB');
    final rawKeys = r.fields['keys'] ?? const <Object?>[];
    if (rawKeys is! List) throw badRequest('keys must be a list of key names');
    final keys = [for (final k in rawKeys) _key(k)];
    final enter = flagField(r, 'enter');
    if ((text == null || text.isEmpty) && keys.isEmpty && !enter) {
      throw badRequest('nothing to send');
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
    if (name is! String) throw badRequest('a key is a name');
    final k = _named[name];
    if (k != null) return (t) => t.keyInput(k);
    final ctrl = _ctrlKey.firstMatch(name);
    if (ctrl != null) {
      final ch = ctrl.group(1)!.codeUnitAt(0);
      return (t) => t.charInput(ch, ctrl: true);
    }
    // Never echoed: the client's text could hold anything.
    throw badRequest('unknown key name; see shellx send --help');
  }

  Future<Map<String, Object?>> read(MuxMessage r) async {
    final pane = _paneArg(r);
    final lines = r.fields['lines'];
    if (lines != null &&
        (lines is! int || lines < 1 || lines > kReadMaxLines)) {
      throw badRequest('lines is 1–$kReadMaxLines');
    }
    final offset = r.fields['offset'] ?? 0;
    if (offset is! int || offset < 0) throw badRequest('bad offset');
    final page = readPage(
      _pane(pane).terminal,
      lines: lines as int?,
      ansi: flagField(r, 'ansi'),
      offset: offset,
    );
    _touchPane(pane);
    return {'text': page.text, 'next': ?page.next};
  }

  /// D21: holds the connection until done; ends at once when the client
  /// goes ([cancelled]).
  Future<Map<String, Object?>> wait(
    MuxMessage r,
    Future<void>? cancelled,
  ) async {
    final ms = r.fields['timeoutMs'] ?? 30000;
    if (ms is! int || ms < 1 || ms > 3600000) {
      throw badRequest('timeout is 1 ms–3600 s');
    }
    // A shell that already ended with 0 left no pane (A3 D7): `send exit`
    // then `wait --exit` still gets its code; a closed one says so (M2).
    if (r.fields['mode'] == 'exit') {
      if (parseTarget(r.fields['pane'], null, forward: _forward) case PaneRef(
        :final id,
      ) when _tabsState.tabOfSession(id) == null) {
        final end = _ref.read(terminalTabsProvider.notifier).paneEnd(id);
        if (end != null) {
          return {'exitCode': end.exitCode, if (end.closed) 'closed': true};
        }
      }
    }
    final pane = _paneArg(r);
    final timeout = Duration(milliseconds: ms);
    final Future<Map<String, Object?>> Function(PaneProbe) start;
    switch (r.fields['mode']) {
      case 'idle':
        final quiet = r.fields['quietMs'] ?? 500;
        if (quiet is! int || quiet < 0 || quiet > 60000) {
          throw badRequest('quiet is 0–60000 ms');
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
            textField(
              r,
              'pattern',
              maxBytes: kPatternMaxBytes,
              limit: '1 KiB',
            ) ??
            (throw badRequest('pattern is needed'));
        try {
          // Compiles only (syntax): the pattern runs off the UI isolate.
          RegExp(pattern, multiLine: true);
        } on FormatException {
          throw badRequest('invalid regular expression');
        }
        final fromNow = flagField(r, 'fromNow');
        start = (p) => waitMatch(
          p,
          IsolateMatchScanner(pattern),
          fromNow: fromNow,
          timeout: timeout,
          cancelled: cancelled,
        );
      default:
        throw badRequest('mode is idle, exit or match');
    }
    _touchPane(pane);
    return start(_probe(pane));
  }

  /// A live view of one pane, for waits and `--cmd`. Throws `not_found`
  /// when the pane is gone.
  PaneProbe _probe(int pane) => _LivePane(_ref, pane, _pane(pane).terminal);
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
  bool get closed =>
      _p == null &&
      (_ref.read(terminalTabsProvider.notifier).paneEnd(id)?.closed ?? false);

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

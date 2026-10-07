import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/ssh_actions.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'notifications_panel.dart' show relativeTime;
import 'remote_marks.dart' show cleanServerText;

export '../window_router.dart' show SshDialogTab;

part 'ssh_connect_parts.dart';

/// How long a server gets to list its tmux sessions before the dialog
/// says it could not: the runner's own limit is 5 s; this bound keeps the
/// dialog from hanging on a runner that never answers.
const Duration _tmuxListBound = Duration(seconds: 8);

/// "Connect to a server" (A8 D41, D42; UI-A8 §4): one dialog, two tabs.
/// Everything typed here is checked ([SshTarget.parse], [isValidRemoteCwd],
/// [isValidTmuxName]) before anything runs; nothing here is ever logged.
class SshConnectDialog extends ConsumerStatefulWidget {
  const SshConnectDialog({
    super.key,
    this.initialTab = SshDialogTab.ssh,
    this.showTitle = true,
  });
  final SshDialogTab initialTab;

  /// False inside the route's dialog, which draws the title itself.
  final bool showTitle;

  @override
  ConsumerState<SshConnectDialog> createState() => _SshConnectDialogState();
}

class _SshConnectDialogState extends ConsumerState<SshConnectDialog> {
  late SshDialogTab _tab = widget.initialTab;
  final _host = TextEditingController();
  final _dir = TextEditingController();
  final _source = TextEditingController();
  final _newName = TextEditingController();
  final _hostFocus = FocusNode();
  final _listFocus = FocusNode(debugLabel: 'tmux list');
  SshSuggestions _suggestions = const SshSuggestions(config: [], recent: []);
  int? _cursor;
  int? _sourceCursor;
  bool _sourceSuggest = false;
  int? _lastTapRow;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _noHook = false;
  String? _hostError;
  String? _dirError;
  String? _sourceError;
  String? _nameError;
  TmuxListResult? _tmux;
  bool _tmuxSlow = false;
  int _tmuxGeneration = 0;
  int _tmuxCursor = 0;

  SshActions get _actions => ref.read(sshActionsProvider);

  /// Windows has no "This computer" to list: its tmux is not one we drive.
  bool get _noLocalTmux => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggestions());
    if (_tab == SshDialogTab.tmux) unawaited(_listTmux());
    _host.addListener(_hostChanged);
    _source.addListener(_sourceChanged);
  }

  /// Controllers also notify for focus and caret moves: only a changed
  /// text counts.
  String _hostText = '';
  String _sourceText = '';

  void _hostChanged() {
    if (_host.text == _hostText) return;
    _hostText = _host.text;
    setState(() {
      _cursor = null;
      _hostError = null;
      _syncHook(_host.text);
    });
  }

  /// The tick follows a server already marked "no hook" (UI-A8 §4.1).
  void _syncHook(String text) {
    final t = SshTarget.parse(text);
    if (t != null) _noHook = !_actions.hookFor(t.key);
  }

  /// A new source empties the list at once (the old answer was another
  /// server's) and cancels a listing in flight; Enter lists again.
  void _sourceChanged() {
    if (_source.text == _sourceText) return;
    _sourceText = _source.text;
    setState(() {
      _tmuxGeneration++; // a listing in flight is for another source now
      _tmux = null;
      _tmuxSlow = false;
      _sourceError = null;
      _sourceCursor = null;
      _sourceSuggest = true;
    });
  }

  Future<void> _loadSuggestions() async {
    final s = await _actions.suggestions();
    if (mounted) setState(() => _suggestions = s);
  }

  @override
  void dispose() {
    for (final c in [_host, _dir, _source, _newName]) {
      c.dispose();
    }
    _hostFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  /// D42: substring, case-insensitive; config group first. The tmux source
  /// pins "This computer" above them (not on Windows).
  List<(String, _Group)> _filtered(
    TextEditingController field, {
    bool pinLocal = false,
  }) {
    final q = field.text.trim().toLowerCase();
    bool keep(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final local = AppLocalizations.of(context).tmuxSourceLocal;
    return [
      if (pinLocal && !_noLocalTmux && keep(local)) (local, _Group.local),
      for (final s in _suggestions.config)
        if (keep(s)) (s, _Group.config),
      for (final s in _suggestions.recent)
        if (keep(s)) (s, _Group.recent),
    ];
  }

  void _close() => ref.read(windowRouterProvider.notifier).close();

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context);
    final rows = _filtered(_host);
    final text = _cursor != null && _cursor! < rows.length
        ? rows[_cursor!].$1
        : _host.text;
    final target = SshTarget.parse(text);
    final dir = _dir.text.trim();
    setState(() {
      _hostError = target == null ? l10n.sshHostInvalid : null;
      _dirError = dir.isNotEmpty && !isValidRemoteCwd(dir)
          ? l10n.sshRemoteDirInvalid
          : null;
    });
    if (target == null || _dirError != null) {
      _hostFocus.requestFocus();
      return;
    }
    final actions = _actions;
    _close(); // D42: at once — sign-in happens in the pane
    try {
      await actions.connect(
        target,
        remoteCwd: dir.isEmpty ? null : dir,
        noHook: _noHook,
      );
    } catch (_) {
      // SshActions shows its own toasts; nothing about the server is kept.
    }
  }

  /// The tmux source: null host and true = this computer; null and false =
  /// not a server name.
  (SshTarget?, bool) get _tmuxSource {
    final text = _source.text.trim();
    if (text.isEmpty || text == AppLocalizations.of(context).tmuxSourceLocal) {
      return (null, true);
    }
    final host = SshTarget.parse(text);
    return (host, host != null);
  }

  void _pickSource(String text) {
    _source.text = text;
    setState(() => _sourceCursor = null);
    unawaited(_listTmux());
  }

  /// ↓ opens the source's suggestions, ↑/↓ move, Enter picks (UI-A8 §4.2).
  KeyEventResult _sourceKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _filtered(_source, pinLocal: true);
    if (rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _sourceCursor = !_sourceSuggest || _sourceCursor == null
            ? 0
            : (_sourceCursor! + 1).clamp(0, rows.length - 1);
        _sourceSuggest = true;
      });
      return KeyEventResult.handled;
    }
    if (_sourceSuggest && key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _sourceCursor = _sourceCursor == null
            ? null
            : (_sourceCursor! - 1).clamp(0, rows.length - 1);
      });
      return KeyEventResult.handled;
    }
    final at = _sourceCursor;
    if (_sourceSuggest &&
        at != null &&
        at < rows.length &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      _pickSource(rows[at].$1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _forgetTap() => _lastTapRow = null;

  /// A first click selects at once; a second on the same row within the
  /// double-click time attaches it.
  void _tapRow(int i, List<TmuxSessionInfo> sessions) {
    _listFocus.requestFocus();
    final now = DateTime.now();
    final second =
        _lastTapRow == i && now.difference(_lastTapAt) <= kDoubleTapTimeout;
    _lastTapRow = i;
    _lastTapAt = now;
    if (second) {
      unawaited(_attach(sessions[i].name));
    } else {
      setState(() => _tmuxCursor = i);
    }
  }

  Future<void> _listTmux() async {
    final (host, valid) = _tmuxSource;
    if (!valid) {
      setState(() {
        _sourceError = AppLocalizations.of(context).sshHostInvalid;
        _tmux = null;
      });
      return;
    }
    final generation = ++_tmuxGeneration;
    _forgetTap();
    _sourceSuggest = false;
    if (host == null && _noLocalTmux) {
      setState(() {
        _sourceError = null;
        _tmux = const TmuxUnavailable();
      });
      return;
    }
    setState(() {
      _sourceError = null;
      _tmux = null;
      _tmuxSlow = false;
      _tmuxCursor = 0;
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted && generation == _tmuxGeneration && _tmux == null) {
          setState(() => _tmuxSlow = true);
        }
      }),
    );
    TmuxListResult result;
    try {
      result = await _actions.listTmux(host).timeout(_tmuxListBound);
    } catch (_) {
      result = const TmuxListFailed(TmuxListFailure.timeout);
    }
    if (mounted && generation == _tmuxGeneration) {
      _forgetTap();
      setState(() => _tmux = result);
    }
  }

  Future<void> _attach(String name, {bool create = false}) async {
    _forgetTap();
    final l10n = AppLocalizations.of(context);
    final (host, valid) = _tmuxSource;
    if (!valid) {
      setState(() => _sourceError = l10n.sshHostInvalid);
      return;
    }
    if (host == null && _noLocalTmux) return;
    // A name from the server is checked like one typed here.
    if (!isValidTmuxName(name)) {
      setState(() => _nameError = l10n.tmuxNameInvalid);
      return;
    }
    final actions = _actions;
    _close();
    try {
      await actions.attachTmux(name, host: host, create: create);
    } catch (_) {
      // SshActions shows its own toasts.
    }
  }

  Future<void> _create() => _attach(_newName.text.trim(), create: true);

  KeyEventResult _hostKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _filtered(_host);
    if (rows.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _cursor = _cursor == null
            ? 0
            : (_cursor! + 1).clamp(0, rows.length - 1);
        _syncHook(rows[_cursor!].$1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _cursor = _cursor == null
            ? null
            : (_cursor! - 1).clamp(0, rows.length - 1);
        if (_cursor != null) _syncHook(rows[_cursor!].$1);
      });
      return KeyEventResult.handled;
    }
    // Tab fills the field with the row and moves on (UI-A8 §4.1).
    if (key == LogicalKeyboardKey.tab &&
        _cursor != null &&
        !HardwareKeyboard.instance.isShiftPressed) {
      final text = rows[_cursor!].$1;
      _host.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return KeyEventResult.ignored;
  }

  /// ↑/↓ move the cursor, Enter attaches it (UI-A8 §6).
  KeyEventResult _listKeys(List<TmuxSessionInfo> sessions, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (sessions.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _tmuxCursor = (_tmuxCursor + 1).clamp(0, sessions.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _tmuxCursor = (_tmuxCursor - 1).clamp(0, sessions.length - 1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_attach(sessions[_tmuxCursor].name));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(l10n.sshDialogTitle, style: ShellxText.dialogTitle),
          const SizedBox(height: ShellxSpace.s12),
        ],
        _TabBar(
          selected: _tab,
          onSelect: (t) {
            setState(() => _tab = t);
            if (t == SshDialogTab.tmux && _tmux == null) {
              unawaited(_listTmux());
            }
          },
        ),
        const SizedBox(height: ShellxSpace.s16),
        if (_tab == SshDialogTab.ssh) ..._sshBody(l10n) else ..._tmuxBody(l10n),
      ],
    );
  }

  List<Widget> _sshBody(AppLocalizations l10n) {
    final rows = _filtered(_host);
    return [
      Text(l10n.sshHostLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      Focus(
        onKeyEvent: _hostKeys,
        canRequestFocus: false,
        skipTraversal: true,
        child: Semantics(
          hint: l10n.sshSuggestionsCount(rows.length),
          child: TextField(
            key: const Key('ssh.host'),
            controller: _host,
            focusNode: _hostFocus,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.sshHostHint,
              errorText: _hostError,
            ),
            onSubmitted: (_) => unawaited(_connect()),
          ),
        ),
      ),
      if (rows.isNotEmpty)
        _SuggestionList(
          rows: rows,
          cursor: _cursor,
          query: _host.text,
          onPick: (s) {
            _host.text = s;
            unawaited(_connect());
          },
        ),
      const SizedBox(height: ShellxSizes.fieldGap),
      Text(l10n.sshRemoteDirLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      TextField(
        key: const Key('ssh.dir'),
        controller: _dir,
        decoration: InputDecoration(hintText: '/srv/app', errorText: _dirError),
        onSubmitted: (_) => unawaited(_connect()),
      ),
      const SizedBox(height: ShellxSpace.s12),
      CheckboxListTile(
        key: const Key('ssh.nohook'),
        value: _noHook,
        onChanged: (v) => setState(() => _noHook = v ?? false),
        title: Text(l10n.sshNoHookLabel, style: ShellxText.dialogBody),
        subtitle: Text(l10n.sshNoHookHelp, style: ShellxText.caption),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: ShellxSpace.s24),
      _Buttons(
        primary: l10n.sshConnectAction,
        primaryKey: const Key('ssh.connect'),
        onPrimary: () => unawaited(_connect()),
        onCancel: _close,
      ),
    ];
  }

  List<Widget> _tmuxBody(AppLocalizations l10n) {
    final result = _tmux;
    final sessions = result is TmuxSessions
        ? result.sessions
        : const <TmuxSessionInfo>[];
    final sourceRows = _filtered(_source, pinLocal: true);
    final (host, _) = _tmuxSource;
    final where = cleanServerText(host?.key ?? l10n.tmuxSourceLocal);
    final cursor = _tmuxCursor.clamp(
      0,
      sessions.isEmpty ? 0 : sessions.length - 1,
    );
    return [
      Text(l10n.tmuxSourceLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      Focus(
        onKeyEvent: _sourceKeys,
        canRequestFocus: false,
        skipTraversal: true,
        child: Semantics(
          hint: l10n.sshSuggestionsCount(sourceRows.length),
          child: TextField(
            key: const Key('tmux.source'),
            controller: _source,
            autofocus: widget.initialTab == SshDialogTab.tmux,
            decoration: InputDecoration(
              hintText: l10n.tmuxSourceLocal,
              errorText: _sourceError,
            ),
            onTap: () => setState(() => _sourceSuggest = true),
            onSubmitted: (_) {
              final rows = _filtered(_source, pinLocal: true);
              final at = _sourceCursor;
              if (_sourceSuggest && at != null && at < rows.length) {
                _pickSource(rows[at].$1);
              } else {
                unawaited(_listTmux());
              }
            },
          ),
        ),
      ),
      if (_sourceSuggest && sourceRows.isNotEmpty)
        _SuggestionList(
          rows: sourceRows,
          cursor: _sourceCursor,
          query: _source.text,
          keyPrefix: 'tmux.suggest',
          onPick: _pickSource,
        ),
      const SizedBox(height: ShellxSpace.s8),
      // One announcement per change: the list's state as it settles.
      Semantics(
        liveRegion: true,
        child: SizedBox(
          height: ShellxSizes.tmuxRow * 4,
          child: switch (result) {
            null => Center(
              child: _tmuxSlow && _sourceError == null
                  ? Text(l10n.tmuxLoading)
                  : const SizedBox.shrink(),
            ),
            TmuxUnavailable() => Center(
              child: Text(l10n.tmuxUnavailable(where)),
            ),
            TmuxListFailed() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.tmuxListFailed(where), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => unawaited(_listTmux()),
                    child: Text(l10n.tmuxRetry),
                  ),
                ],
              ),
            ),
            TmuxSessions() when sessions.isEmpty => Center(
              child: Text(l10n.tmuxEmpty),
            ),
            TmuxSessions() => Focus(
              focusNode: _listFocus,
              onKeyEvent: (_, event) => _listKeys(sessions, event),
              child: ListView(
                children: [
                  for (final (i, s) in sessions.indexed)
                    _TmuxRow(
                      key: Key('tmux.row.${s.name}'),
                      info: s,
                      selected: i == cursor,
                      onTapDown: () => _tapRow(i, sessions),
                    ),
                ],
              ),
            ),
          },
        ),
      ),
      const SizedBox(height: ShellxSizes.fieldGap),
      Text(l10n.tmuxNewLabel, style: ShellxText.label),
      const SizedBox(height: ShellxSizes.labelGap),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('tmux.new'),
              controller: _newName,
              decoration: InputDecoration(errorText: _nameError),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => unawaited(_create()),
            ),
          ),
          const SizedBox(width: ShellxSpace.s8),
          OutlinedButton(
            key: const Key('tmux.create'),
            onPressed: () => unawaited(_create()),
            child: Text(l10n.tmuxCreateAction),
          ),
        ],
      ),
      const SizedBox(height: ShellxSpace.s24),
      _Buttons(
        primary: l10n.tmuxAttachAction,
        primaryKey: const Key('tmux.attach'),
        onPrimary: sessions.isEmpty
            ? null
            : () => unawaited(_attach(sessions[cursor].name)),
        onCancel: _close,
      ),
    ];
  }
}

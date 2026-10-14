import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';
import 'agent_status_notifier.dart';
import 'local_sessions_provider.dart';
import 'sidebar_workspaces.dart';
import 'terminal_tabs.dart';

enum AttentionKind { message, command, bell }

/// A7 D23: the "tab" of entries from `shellx notify` outside a pane.
/// Session ids start at 1 (`sessionIdAllocator`), so 0 is never a tab.
const int kCommandLineTabId = 0;

/// A tab's unread notifications since it was last read (A4 D8, D9).
@immutable
final class TabUnread {
  const TabUnread({
    required this.count,
    required this.panes,
    required this.notice,
    required this.kind,
    required this.at,
  });
  final int count;

  /// A3 D18: unread per pane (session id); [count] is their sum.
  final Map<int, int> panes;

  /// The last one (the sidebar line). Kept as the notice, not its words,
  /// so the line is worded in the language shown now.
  final SessionNotice notice;
  final AttentionKind kind;
  final DateTime at;

  /// The sidebar line (D9) in [l10n]'s language.
  String text(AppLocalizations l10n) => noticeText(notice, l10n);

  /// A command that ended with a non-zero code (the ✗ line).
  bool get failed => noticeFailed(notice);
}

/// One panel entry (A4 D11). Text lives only in memory (N9).
@immutable
final class AttentionEntry {
  const AttentionEntry({
    required this.seq,
    required this.tabId,
    required this.paneId,
    required this.tabLabel,
    required this.kind,
    required this.notice,
    required this.at,
    this.read = false,
    this.repeat = 1,
    this.closed = false,
  });
  final int seq;
  final int tabId;

  /// A3 D18: the pane (session id) it came from.
  final int paneId;

  /// The label it arrived with ([TerminalTab.noticeLabel]: the sending
  /// pane's in a split tab), shown once the tab or the pane is gone.
  final String tabLabel;
  final AttentionKind kind;

  /// What arrived; worded at render time ([text]), in the language shown.
  final SessionNotice notice;
  final DateTime at;
  final bool read;

  /// Merged consecutive bells ("Chuông ×N").
  final int repeat;

  /// The tab is gone: shown as "Tab đã đóng", not jumpable.
  final bool closed;

  /// The panel's line 2 (D9) in [l10n]'s language.
  String text(AppLocalizations l10n) => noticeText(notice, l10n);

  /// A command that ended with a non-zero code (the ✗ line).
  bool get failed => noticeFailed(notice);

  AttentionEntry copyWith({
    bool? read,
    int? repeat,
    DateTime? at,
    bool? closed,
  }) => AttentionEntry(
    seq: seq,
    tabId: tabId,
    paneId: paneId,
    tabLabel: tabLabel,
    kind: kind,
    notice: notice,
    at: at ?? this.at,
    read: read ?? this.read,
    repeat: repeat ?? this.repeat,
    closed: closed ?? this.closed,
  );
}

@immutable
final class AttentionState {
  const AttentionState({this.unread = const {}, this.history = const []});

  final Map<int, TabUnread> unread;

  /// Newest first, at most [TabAttention.historyLimit].
  final List<AttentionEntry> history;

  int get totalUnread => unread.values.fold(0, (sum, u) => sum + u.count);
  bool hasUnread(int tabId) => unread.containsKey(tabId);

  /// A3 D18: the pane rings.
  bool paneHasUnread(int tabId, int paneId) =>
      (unread[tabId]?.panes[paneId] ?? 0) > 0;

  Set<int> unreadPanes(int tabId) =>
      unread[tabId]?.panes.keys.toSet() ?? const {};
}

/// A notice the user has not seen (not D7): system notification, taskbar
/// flash, screen-reader announcement.
@immutable
final class AttentionArrival {
  const AttentionArrival({
    required this.tabId,
    required this.paneId,
    required this.kind,
    required this.text,
    required this.at,
    this.title,
  });
  final int tabId;

  /// A3 D18: the pane (session id) it came from; it names the
  /// notification in a split tab ([TerminalTab.noticeLabel]).
  final int paneId;
  final AttentionKind kind;
  final String text;
  final DateTime at;

  /// A7 D23: a command-line entry's own title (tabs are titled by their
  /// label instead).
  final String? title;
}

/// UI-A4 §2.1, D8.
String unreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// C0, DEL, C1 and the Unicode line/paragraph separators: anything that
/// would break the one line (D9).
final _controls = RegExp(r'\s*[\x00-\x1f\x7f-\x9f\u2028\u2029]+\s*');

String _oneLine(String? text) => (text ?? '').replaceAll(_controls, ' ').trim();

/// A4 D9: the line a notice shows, on one line.
String noticeText(SessionNotice n, AppLocalizations l10n) {
  switch (n.kind) {
    case SessionNoticeKind.message:
      final title = _oneLine(n.title);
      final body = _oneLine(n.body);
      if (title.isEmpty) return body;
      return body.isEmpty ? title : '$title: $body';
    case SessionNoticeKind.command:
      final command = n.command;
      if (command == null) return '';
      return _oneLine(NotificationText(l10n.localeName).commandBody(command));
    case SessionNoticeKind.bell:
      return l10n.attentionBell;
  }
}

/// A command notice whose command ended with a non-zero code.
bool noticeFailed(SessionNotice n) =>
    n.kind == SessionNoticeKind.command && (n.command?.exitCode ?? 0) != 0;

AttentionKind _kindOf(SessionNoticeKind kind) => switch (kind) {
  SessionNoticeKind.message => AttentionKind.message,
  SessionNoticeKind.command => AttentionKind.command,
  SessionNoticeKind.bell => AttentionKind.bell,
};

final tabAttentionProvider = NotifierProvider<TabAttention, AttentionState>(
  TabAttention.new,
);

/// A subscription made by [listenAttention].
final class AttentionListener {
  AttentionListener._();
  ProviderSubscription<TabAttention>? _notifier;
  StreamSubscription<AttentionArrival>? _arrivals;
  StreamSubscription<int>? _reads;

  void close() {
    _notifier?.close();
    _notifier = null;
    unawaited(_arrivals?.cancel());
    unawaited(_reads?.cancel());
    _arrivals = null;
    _reads = null;
  }
}

/// [onArrival] / [onRead] for [TabAttention.arrivals] / [TabAttention.reads]
/// that survive a rebuild of the provider (the local sessions change):
/// the streams live as long as the notifier, and a new notifier gets a new
/// subscription. Building the provider here (fireImmediately) also means
/// no notice is missed.
AttentionListener listenAttention(
  ProviderContainer container, {
  void Function(AttentionArrival arrival)? onArrival,
  void Function(int tabId)? onRead,
}) {
  final listener = AttentionListener._();
  void attach(TabAttention attention) {
    unawaited(listener._arrivals?.cancel());
    unawaited(listener._reads?.cancel());
    listener._arrivals = onArrival == null
        ? null
        : attention.arrivals.listen(onArrival);
    listener._reads = onRead == null ? null : attention.reads.listen(onRead);
  }

  listener._notifier = container.listen<TabAttention>(
    tabAttentionProvider.notifier,
    (previous, next) {
      if (!identical(previous, next)) attach(next);
    },
    fireImmediately: true,
  );
  return listener;
}

/// Which tabs want the user (A4 N2–N5, D4, D7–D13, D26). UI state of this
/// window only; the agent just reports notices.
class TabAttention extends Notifier<AttentionState> {
  static const int historyLimit = 50;

  /// A7 D23: command-line entries kept, apart from the tabs' [historyLimit]
  /// (a `shellx notify` flood never pushes a tab's entry out).
  static const int commandLineLimit = 10;
  static const Duration dwell = Duration(seconds: 1);

  final _arrivals = StreamController<AttentionArrival>.broadcast(sync: true);
  final _reads = StreamController<int>.broadcast(sync: true);
  Timer? _dwell;

  /// (tab id, pane id) the dwell timer reads (A3 D18).
  (int, int)? _dwellFor;
  int _seq = 0;

  /// Notices the user has not seen. Consumers subscribe through
  /// [listenAttention], which follows a new notifier if Riverpod ever
  /// makes one.
  Stream<AttentionArrival> get arrivals => _arrivals.stream;

  /// Tab ids that were marked read (their system notification is removed).
  /// Same lifetime rule as [arrivals].
  Stream<int> get reads => _reads.stream;

  @override
  AttentionState build() {
    final local = ref.watch(localSessionsProvider);
    final sub = local.notices.listen(_onNotice);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) {
      _dropGone(tabs);
      _armDwell();
    });
    // The sources, not the derived windowActiveProvider (see its doc).
    ref.listen<bool>(windowFocusProvider, (_, _) => _armDwell());
    ref.listen<bool>(
      windowRouterProvider.select((w) => w.visible),
      (_, _) => _armDwell(),
    );
    // The streams stay open: Riverpod keeps this notifier across a
    // rebuild (onDispose runs then too), and its listeners stay with it.
    ref.onDispose(() {
      unawaited(sub.cancel());
      _cancelDwell();
    });
    return const AttentionState();
  }

  /// Every pane of tab [tabId].
  void markRead(int tabId) => _markRead({tabId});

  /// A3 D18: one pane read (the 1 s dwell on the focused pane). The tab's
  /// system notification goes ([reads]) only when no pane is left unread.
  void markPaneRead(int tabId, int paneId) {
    final before = state.unread[tabId];
    if (before == null || !before.panes.containsKey(paneId)) return;
    final panes = Map.of(before.panes)..remove(paneId);
    final unread = Map.of(state.unread);
    if (panes.isEmpty) {
      unread.remove(tabId);
    } else {
      unread[tabId] = TabUnread(
        count: before.count - before.panes[paneId]!,
        panes: panes,
        notice: before.notice,
        kind: before.kind,
        at: before.at,
      );
    }
    state = AttentionState(
      unread: unread,
      history: [
        for (final e in state.history)
          e.tabId == tabId && e.paneId == paneId && !e.read
              ? e.copyWith(read: true)
              : e,
      ],
    );
    if (_dwellFor == (tabId, paneId)) _cancelDwell();
    if (panes.isEmpty) _reads.add(tabId);
  }

  /// One state update for all tabs, and the command-line entries.
  void markAllRead() => _markRead({...state.unread.keys, kCommandLineTabId});

  /// A7 D23: a `shellx notify` from outside a pane — a panel entry, no
  /// badge, no ring, never closed. Arrives (for its system notification,
  /// treated as "window not in front") with its own [title].
  void addCommandLine({String? title, required String body}) {
    final notice = SessionNotice(
      sessionId: kCommandLineTabId,
      kind: SessionNoticeKind.message,
      at: DateTime.now(),
      title: title,
      body: body,
    );
    state = AttentionState(
      unread: state.unread,
      history: _capped([
        AttentionEntry(
          seq: _seq++,
          tabId: kCommandLineTabId,
          paneId: kCommandLineTabId,
          tabLabel: ref.read(appL10nProvider).cliNoticeSource,
          kind: AttentionKind.message,
          notice: notice,
          at: notice.at,
        ),
        ...state.history,
      ]),
    );
    _arrivals.add(
      AttentionArrival(
        tabId: kCommandLineTabId,
        paneId: kCommandLineTabId,
        kind: AttentionKind.message,
        text: _oneLine(body),
        at: notice.at,
        title: title,
      ),
    );
  }

  void _markRead(Set<int> tabIds) {
    final had = [
      for (final id in state.unread.keys)
        if (tabIds.contains(id)) id,
      // A7 D23: command-line entries have no unread count; their system
      // notification goes too.
      if (tabIds.contains(kCommandLineTabId) &&
          state.history.any((e) => !e.read && e.tabId == kCommandLineTabId))
        kCommandLineTabId,
    ];
    final stale = state.history.any((e) => !e.read && tabIds.contains(e.tabId));
    final dwelling = _dwellFor;
    if (dwelling != null && tabIds.contains(dwelling.$1)) _cancelDwell();
    if (had.isEmpty && !stale) return;
    state = AttentionState(
      unread: Map.of(state.unread)..removeWhere((id, _) => tabIds.contains(id)),
      history: [
        for (final e in state.history)
          !e.read && tabIds.contains(e.tabId) ? e.copyWith(read: true) : e,
      ],
    );
    had.forEach(_reads.add);
  }

  /// D13: the next tab with unread after the selected one, in sidebar
  /// order (collapsed workspaces included), wrapping.
  int? nextUnread() {
    if (state.unread.isEmpty) return null;
    final order = ref.read(sidebarWorkspacesProvider).orderedTabIds;
    if (order.isEmpty) return null;
    final start = order.indexOf(
      ref.read(terminalTabsProvider).selectedId ?? -1,
    );
    for (var step = 1; step <= order.length; step++) {
      final id = order[(start + step) % order.length];
      if (state.hasUnread(id)) return id;
    }
    return null;
  }

  /// D16 / panel Enter / next unread: select, expand its workspace, focus
  /// the pane with the newest unread notice (A3 D18), read at once (the
  /// user asked), keyboard to the terminal. False when the tab is gone.
  bool jumpTo(int tabId) {
    if (!ref.read(terminalTabsProvider).tabs.any((t) => t.id == tabId)) {
      return false;
    }
    final newest = state.history
        .where((e) => e.tabId == tabId && !e.read)
        .map((e) => e.paneId)
        .firstOrNull;
    final tabs = ref.read(terminalTabsProvider.notifier);
    ref.read(sidebarWorkspacesProvider.notifier).reveal(tabId);
    tabs.select(tabId);
    // V2-1 D13: an AI pane too (negative ids: never a `-1` default here).
    final tab = newest == null
        ? null
        : ref.read(terminalTabsProvider).tabOfPane(newest);
    if (newest != null && tab?.id == tabId) tabs.focusPane(newest);
    markRead(tabId);
    ref.read(terminalFocusRequestProvider.notifier).request();
    return true;
  }

  // ---- internals --------------------------------------------------------

  bool get _active => readWindowActive(ref.read);

  void _onNotice(SessionNotice notice) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(notice.sessionId);
    if (tab == null) return; // not (or no longer) a pane of this window
    // A12 D10: what a hook event already told (an OSC / bell right after
    // it) is not told twice.
    if (ref.read(agentStatusProvider.notifier).swallowNotice(notice)) return;
    _record(tabs, tab, notice);
  }

  /// V2-1 D13: a notice from AI pane [paneId] of tab [tabId] (no session
  /// carries it): the same path as a pane's own notice — the focused-pane
  /// rule, the badge, the panel and the system notification with its
  /// limits (A4).
  void addAiNotice(
    int tabId,
    int paneId, {
    String? title,
    required String body,
  }) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null || !tab.aiPanes.containsKey(paneId)) return;
    _record(
      tabs,
      tab,
      SessionNotice(
        sessionId: paneId,
        kind: SessionNoticeKind.message,
        at: DateTime.now(),
        title: title,
        body: body,
      ),
    );
  }

  void _record(TerminalTabsState tabs, TerminalTab tab, SessionNotice notice) {
    final pane = notice.sessionId;
    // A3 D18: only the focused pane of the selected tab is in view.
    final seen =
        tabs.selectedId == tab.id && tab.focusedPaneId == pane && _active;
    if (seen && notice.kind == SessionNoticeKind.bell) return; // D7
    final kind = _kindOf(notice.kind);
    final history = _withEntry(tab, pane, kind, notice, read: seen);
    if (seen) {
      state = AttentionState(unread: state.unread, history: history);
      return;
    }
    final before = state.unread[tab.id];
    state = AttentionState(
      unread: {
        ...state.unread,
        tab.id: TabUnread(
          count: (before?.count ?? 0) + 1,
          panes: {...?before?.panes, pane: (before?.panes[pane] ?? 0) + 1},
          notice: notice,
          kind: kind,
          at: notice.at,
        ),
      },
      history: history,
    );
    // Worded now: arrivals are handled at once, in the language shown.
    final text = noticeText(notice, ref.read(appL10nProvider));
    _arrivals.add(
      AttentionArrival(
        tabId: tab.id,
        paneId: pane,
        kind: kind,
        text: text,
        at: notice.at,
      ),
    );
    _armDwell();
  }

  List<AttentionEntry> _withEntry(
    TerminalTab tab,
    int paneId,
    AttentionKind kind,
    SessionNotice notice, {
    required bool read,
  }) {
    final at = notice.at;
    final history = state.history;
    final first = history.firstOrNull;
    if (kind == AttentionKind.bell &&
        first != null &&
        first.kind == AttentionKind.bell &&
        first.tabId == tab.id &&
        first.paneId == paneId &&
        first.read == read) {
      return [
        first.copyWith(repeat: first.repeat + 1, at: at),
        ...history.skip(1),
      ];
    }
    return _capped([
      AttentionEntry(
        seq: _seq++,
        tabId: tab.id,
        paneId: paneId,
        tabLabel: tab.noticeLabel(paneId),
        kind: kind,
        notice: notice,
        at: at,
        read: read,
      ),
      ...history,
    ]);
  }

  /// Newest first: the newest [historyLimit] tab entries and the newest
  /// [commandLineLimit] command-line ones (A7 D23); neither pushes the
  /// other out.
  static List<AttentionEntry> _capped(List<AttentionEntry> history) {
    var tabs = 0;
    var commandLine = 0;
    return [
      for (final e in history)
        if (e.tabId == kCommandLineTabId
            ? ++commandLine <= commandLineLimit
            : ++tabs <= historyLimit)
          e,
    ];
  }

  /// D26: tabs that went away lose their unread; history keeps them,
  /// closed and read (nothing is left to read there). A3 D18: so do panes
  /// that left a tab that is still here (their entries stay jumpable, read).
  /// Command-line entries (A7 D23) never had a tab: they stay as they are.
  void _dropGone(TerminalTabsState tabs) {
    final present = {
      for (final t in tabs.tabs) t.id: t,
      kCommandLineTabId: null,
    };
    bool paneGone(int tabId, int paneId) =>
        tabId != kCommandLineTabId &&
        !(present[tabId]?.hasPane(paneId) ?? false);
    final unread = <int, TabUnread>{};
    final emptied = <int>[];
    var changed = false;
    for (final MapEntry(key: id, value: u) in state.unread.entries) {
      final panes = {
        for (final MapEntry(key: p, value: n) in u.panes.entries)
          if (!paneGone(id, p)) p: n,
      };
      if (panes.isEmpty) {
        emptied.add(id);
        changed = true;
      } else if (panes.length == u.panes.length) {
        unread[id] = u;
      } else {
        changed = true;
        unread[id] = TabUnread(
          count: panes.values.fold(0, (a, b) => a + b),
          panes: panes,
          notice: u.notice,
          kind: u.kind,
          at: u.at,
        );
      }
    }
    final stale = state.history.any(
      (e) =>
          (!e.closed && !present.containsKey(e.tabId)) ||
          (!e.read && paneGone(e.tabId, e.paneId)),
    );
    if (!changed && !stale) return;
    state = AttentionState(
      unread: unread,
      history: [
        for (final e in state.history)
          if (!e.closed && !present.containsKey(e.tabId))
            e.copyWith(closed: true, read: true)
          else if (!e.read && paneGone(e.tabId, e.paneId))
            e.copyWith(read: true)
          else
            e,
      ],
    );
    emptied.forEach(_reads.add);
  }

  /// D10: one timer for the selected tab's focused pane (A3 D18) while it
  /// has unread and the window is active; unchanged conditions keep the
  /// running timer.
  void _armDwell() {
    if (!ref.mounted) return;
    final tab = ref.read(terminalTabsProvider).selected;
    final key = tab == null ? null : (tab.id, tab.focusedPaneId);
    if (key == null || !state.paneHasUnread(key.$1, key.$2) || !_active) {
      _cancelDwell();
      return;
    }
    if (_dwellFor == key && (_dwell?.isActive ?? false)) return;
    _cancelDwell();
    _dwellFor = key;
    _dwell = Timer(dwell, () {
      _dwellFor = null;
      if (!ref.mounted) return;
      final now = ref.read(terminalTabsProvider).selected;
      if (now?.id == key.$1 && now?.focusedPaneId == key.$2 && _active) {
        markPaneRead(key.$1, key.$2);
      }
    });
  }

  void _cancelDwell() {
    _dwell?.cancel();
    _dwell = null;
    _dwellFor = null;
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../config/config_controller.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart' show ShellxScrollbar;

/// UI-A4 §5.2: < 60 s "now"; < 60 min "{n} min"; < 24 h "{n} h"; older
/// and from yesterday "Yesterday HH:mm"; before that "MMM d, HH:mm" (vi
/// "dd/MM HH:mm"), 24 h clock. A time slightly ahead (clock skew) is "now".
String relativeTime(DateTime at, DateTime now, AppLocalizations l10n) {
  final d = now.difference(at);
  if (d.inSeconds < 60) return l10n.notificationsTimeNow;
  if (d.inMinutes < 60) return l10n.notificationsTimeMinutes(d.inMinutes);
  if (d.inHours < 24) return l10n.notificationsTimeHours(d.inHours);
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  if (at.year == yesterday.year &&
      at.month == yesterday.month &&
      at.day == yesterday.day) {
    return l10n.notificationsTimeYesterday(time);
  }
  return l10n.notificationsTimeDate(
    l10n.notificationsMonthShort('m${at.month}'),
    '${at.day}',
    two(at.day),
    time,
  );
}

/// UI-A4 §5: the last 50 notifications, newest first, keyboard first
/// (A4 N5). The page places it, owns the open state and gives the
/// keyboard back on [onClose].
class NotificationsPanel extends ConsumerStatefulWidget {
  const NotificationsPanel({super.key, required this.onClose});

  /// Esc, or a jump to a tab: the page closes the panel.
  final VoidCallback onClose;

  @override
  ConsumerState<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<NotificationsPanel> {
  /// The thumb with its margin on both sides.
  static const double _scrollGutter =
      ShellxSizes.scrollbarThickness + 2 * ShellxSizes.scrollbarMargin;

  final _list = FocusNode(debugLabel: 'notifications panel');
  final _markAll = FocusNode(debugLabel: 'mark all as read');
  final _scroll = ScrollController();

  /// The keyboard cursor, by entry: new notifications arriving while the
  /// panel is open shift the indexes, not the cursor.
  int? _cursorSeq;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final history = ref.read(tabAttentionProvider).history;
    // UI-A4 §5.3: the first unread, else the first.
    _cursorSeq =
        (history.where((e) => !e.read).firstOrNull ?? history.firstOrNull)?.seq;
    // UI-A4 §5.2: relative times refresh every 30 s while open.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _list.addListener(_onFocus);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _list.requestFocus();
      _scrollToCursor(ref.read(tabAttentionProvider).history);
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).notificationsPanelOpened(history.length),
          Directionality.of(context),
        ),
      );
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _list.removeListener(_onFocus);
    _list.dispose();
    _markAll.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  void _onHighlightMode(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  int _cursorIn(List<AttentionEntry> items) {
    final i = items.indexWhere((e) => e.seq == _cursorSeq);
    return i < 0 ? 0 : i;
  }

  double _itemExtent(BuildContext context) {
    // UI-A4 §1.3: max(52, scale(16) + scale(18) + 18).
    final scaler = MediaQuery.textScalerOf(context);
    return max(ShellxSizes.panelItem, scaler.scale(16) + scaler.scale(18) + 18);
  }

  void _scrollToCursor(List<AttentionEntry> items) {
    if (!_scroll.hasClients || items.isEmpty) return;
    final extent = _itemExtent(context);
    final top = _cursorIn(items) * extent;
    final view = _scroll.position;
    if (top < view.pixels) {
      _scroll.jumpTo(top);
    } else if (top + extent > view.pixels + view.viewportDimension) {
      _scroll.jumpTo(top + extent - view.viewportDimension);
    }
  }

  void _open(AttentionEntry e) {
    if (e.closed) {
      // UI-A4 §5.3: nothing to jump to; say why.
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          AppLocalizations.of(context).notificationsTabClosed,
          Directionality.of(context),
        ),
      );
      return;
    }
    widget.onClose();
    final attention = ref.read(tabAttentionProvider.notifier);
    if (e.tabId == kCommandLineTabId) {
      // A7 D23: no tab to go to; the window is already in front.
      attention.markRead(kCommandLineTabId);
      return;
    }
    attention.jumpTo(e.tabId);
  }

  /// The list's keys (UI-A4 §5.3). Repeats move the cursor too.
  KeyEventResult _listKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored; // window shortcuts
    }
    final items = ref.read(tabAttentionProvider).history;
    void move(int to) {
      if (items.isEmpty) return;
      setState(() => _cursorSeq = items[to.clamp(0, items.length - 1)].seq);
      _scrollToCursor(items);
    }

    final cursor = _cursorIn(items);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        move(cursor + 1);
      case LogicalKeyboardKey.arrowUp:
        move(cursor - 1);
      case LogicalKeyboardKey.home:
        move(0);
      case LogicalKeyboardKey.end:
        move(items.length - 1);
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        // Held down, Enter must not open entry after entry.
        if (event is KeyDownEvent && items.isNotEmpty) _open(items[cursor]);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The whole panel's keys: Esc closes; Tab / Shift+Tab stay inside, on
  /// the list and "Mark all as read" (UI-A4 §5.3 focus trap).
  KeyEventResult _panelKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored; // Ctrl+Tab and the other shortcuts
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (event is KeyDownEvent) widget.onClose();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        // Two stops, so Tab and Shift+Tab both go to the other one; a
        // disabled button is no stop.
        final canMarkAll = ref.read(tabAttentionProvider).totalUnread > 0;
        if (_list.hasFocus && canMarkAll) {
          _markAll.requestFocus();
        } else {
          _list.requestFocus();
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The footer hint follows a reload; no hint when unbound (A9 D29).
    ref.watch(shellxConfigProvider.select((s) => s.bindings));
    final nextUnread = nextUnreadShortcutLabel();
    final attention = ref.watch(tabAttentionProvider);
    final tabs = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final items = attention.history;
    final now = DateTime.now();
    // UI-A4 §5.2: min(480, window height − 64), from the window itself.
    final view = View.of(context);
    final height = view.physicalSize.height / view.devicePixelRatio;
    final extent = _itemExtent(context);
    final maxHeight = max(0.0, min(ShellxSizes.panelMaxHeight, height - 64));
    // Border, padding, header, its line and the footer around the list.
    final listMax =
        maxHeight -
        2 -
        2 * ShellxSpace.s4 -
        ShellxSizes.panelHeader -
        1 -
        ShellxSizes.panelFooter;
    final overflows = items.length * extent > listMax;
    final markAllEnabled =
        attention.totalUnread > 0 ||
        items.any((e) => e.tabId == kCommandLineTabId && !e.read);
    final cursor = _cursorIn(items);
    final keyboardRing =
        _list.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final byId = {for (final t in tabs.tabs) t.id: t};

    _PanelEntry entry(AttentionEntry e) {
      // The name now (renamed since?), else the last one it had. In a split
      // tab, the pane that sent it (final ruling m-6); once that pane is
      // gone, the name it arrived with.
      final tab = byId[e.tabId];
      final gone =
          tab == null || (tab.isSplit && !tab.panes.containsKey(e.paneId));
      // A7 D23: "Command line", in the language shown now.
      final name = e.tabId == kCommandLineTabId
          ? l10n.cliNoticeSource
          : gone
          ? e.tabLabel
          : tab.noticeLabel(e.paneId);
      final ws = !e.closed && sidebar.showHeaders
          ? sidebar.workspaceOf(e.tabId)
          : null;
      final wsName = ws == null
          ? null
          : sidebar.workspace(ws)?.displayName(l10n);
      final text = e.kind == AttentionKind.bell && e.repeat > 1
          ? l10n.attentionBellRepeat(e.repeat)
          : e.text(l10n);
      final time = relativeTime(e.at, now, l10n);
      return _PanelEntry(
        line1: e.closed
            ? '${l10n.notificationsTabClosed} · $name'
            : wsName == null
            ? name
            : '$name · $wsName',
        text: text,
        time: time,
        // UI-A4 §8: tab, [workspace], text, time, [unread], [Tab closed].
        semantics: [
          name,
          ?wsName,
          text,
          time,
          if (!e.read) l10n.notificationsItemUnread,
          if (e.closed) l10n.notificationsTabClosed,
        ].join(', '),
      );
    }

    final header = SizedBox(
      height: ShellxSizes.panelHeader,
      child: Row(
        children: [
          const SizedBox(width: ShellxSpace.s8),
          Expanded(
            child: Text(
              l10n.notificationsPanelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
          ),
          Opacity(
            // UI-A4 §5.2: 38 % with nothing unread.
            opacity: markAllEnabled ? 1 : ShellxDesktopColors.disabledOpacity,
            child: TextButton(
              key: const Key('panel.markAll'),
              focusNode: _markAll,
              onPressed: markAllEnabled
                  ? () {
                      ref.read(tabAttentionProvider.notifier).markAllRead();
                      // Disabled now: the keyboard goes back to the list.
                      _list.requestFocus();
                    }
                  : null,
              style: _markAllStyle(context),
              child: Text(l10n.attentionMarkAllRead),
            ),
          ),
        ],
      ),
    );

    final Widget body;
    if (items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(ShellxSpace.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.notifications_none,
                size: ShellxSizes.panelEmptyIcon,
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s8),
            Text(
              l10n.notificationsPanelEmptyTitle,
              textAlign: TextAlign.center,
              style: ShellxText.body.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s4),
            Text(
              l10n.notificationsPanelEmptyBody,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    } else {
      // Always shown while the list overflows: entries below the fold
      // must not look like they do not exist (UI-A4 §5.2). The items then
      // leave the thumb its own gutter, so it never covers the time or
      // the cursor ring.
      body = ShellxScrollbar(
        controller: _scroll,
        alwaysVisible: true,
        child: ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          padding: EdgeInsets.only(right: overflows ? _scrollGutter : 0),
          itemCount: items.length,
          itemExtent: extent,
          itemBuilder: (_, i) {
            final e = items[i];
            return _PanelItem(
              key: Key('panel.item.${e.seq}'),
              entry: entry(e),
              unread: !e.read,
              closed: e.closed,
              failed: e.failed,
              cursor: i == cursor,
              keyboardRing: i == cursor && keyboardRing,
              // Where screen readers place the cursor while the list holds
              // the keyboard (like the sidebar's rows, D14).
              focused: i == cursor && _list.hasPrimaryFocus,
              onTap: () {
                setState(() => _cursorSeq = e.seq);
                _open(e);
              },
            );
          },
        ),
      );
    }

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.notificationsPanelTitle,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _panelKey(event),
        child: Container(
          key: const Key('panel'),
          width: ShellxSizes.panelWidth,
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.all(ShellxSpace.s4),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
            boxShadow: ShellxShadows.e1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Container(height: 1, color: ShellxDesktopColors.line),
              // The list's single stop: the cursor moves inside it.
              Flexible(
                child: Focus(
                  focusNode: _list,
                  onKeyEvent: (_, event) => _listKey(event),
                  child: body,
                ),
              ),
              if (items.isNotEmpty && nextUnread != null)
                SizedBox(
                  height: ShellxSizes.panelFooter,
                  child: Padding(
                    padding: const EdgeInsets.only(left: ShellxSpace.s8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.notificationsPanelNextHint(nextUnread),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellxText.caption.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// UI-A4 §5.2: `small` w600 `accent`, 28 high, padding 0/8, hover
  /// `rowHover` `r6`, the A1 focus ring for keyboard focus.
  static ButtonStyle _markAllStyle(BuildContext context) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, ShellxSizes.textButton)),
    fixedSize: const WidgetStatePropertyAll(
      Size.fromHeight(ShellxSizes.textButton),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      uiFont(
        ShellxText.small.copyWith(fontWeight: FontWeight.w600),
        Theme.of(context).textTheme,
      ),
    ),
    // Disabled stays `accent`: the Opacity around it dims it once.
    foregroundColor: const WidgetStatePropertyAll(ShellxDesktopColors.accent),
    animationDuration: ShellxMotion.of(context, ShellxMotion.fast),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Colors.transparent
          : states.contains(WidgetState.pressed)
          ? ShellxDesktopColors.rowPressed
          : states.contains(WidgetState.hovered)
          ? ShellxDesktopColors.rowHover
          : Colors.transparent,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? const BorderSide(
              color: ShellxDesktopColors.accent,
              width: ShellxSizes.focusRing,
            )
          : null,
    ),
  );
}

/// What one item shows and says.
final class _PanelEntry {
  const _PanelEntry({
    required this.line1,
    required this.text,
    required this.time,
    required this.semantics,
  });
  final String line1;
  final String text;
  final String time;
  final String semantics;
}

/// UI-A4 §5.2 item: 52, `r6`, padding 8/8; hover `rowHover`, keyboard
/// cursor `rowSelected` (+ the 2 px ring for keyboard focus), pressed
/// `rowPressed`. A closed tab's entry has no hover and the default cursor.
class _PanelItem extends StatefulWidget {
  const _PanelItem({
    super.key,
    required this.entry,
    required this.unread,
    required this.closed,
    this.failed = false,
    required this.cursor,
    required this.keyboardRing,
    required this.focused,
    required this.onTap,
  });

  final _PanelEntry entry;
  final bool unread;
  final bool closed;

  /// A command that ended non-zero: the unread dot is `err`.
  final bool failed;
  final bool cursor;
  final bool keyboardRing;
  final bool focused;
  final VoidCallback onTap;

  @override
  State<_PanelItem> createState() => _PanelItemState();
}

class _PanelItemState extends State<_PanelItem> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final closed = widget.closed;
    final entry = widget.entry;
    final fill = _pressed && !closed
        ? ShellxDesktopColors.rowPressed
        : widget.cursor
        ? ShellxDesktopColors.rowSelected
        : _hover && !closed
        ? ShellxDesktopColors.rowHover
        : null;
    final secondary = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Semantics(
      button: !closed,
      selected: widget.cursor,
      focused: widget.focused,
      label: entry.semantics,
      onTap: closed ? null : widget.onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: closed ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            padding: const EdgeInsets.all(ShellxSpace.s8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            // In front, so the ring never pushes the content (A1 §3). On a
            // closed tab's entry (Enter does nothing) the ring is `dim`.
            foregroundDecoration: widget.keyboardRing
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(ShellxRadius.r6),
                    border: Border.all(
                      color: closed
                          ? ShellxDesktopColors.dim
                          : ShellxDesktopColors.accent,
                      width: ShellxSizes.focusRing,
                    ),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ShellxSizes.panelUnreadSlot,
                  height: MediaQuery.textScalerOf(context).scale(16),
                  child: widget.unread
                      ? Center(
                          child: Container(
                            key: const Key('panel.item.dot'),
                            width: ShellxSizes.bellDot,
                            height: ShellxSizes.bellDot,
                            decoration: BoxDecoration(
                              color: widget.failed
                                  ? ShellxDesktopColors.err
                                  : ShellxDesktopColors.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.line1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: secondary,
                            ),
                          ),
                          const SizedBox(width: ShellxSpace.s8),
                          Text(
                            entry.time,
                            maxLines: 1,
                            style: ShellxText.caption.copyWith(
                              color: ShellxDesktopColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ShellxSpace.s2),
                      Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellxText.body.copyWith(
                          color: widget.unread
                              ? ShellxDesktopColors.textPrimary
                              : ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

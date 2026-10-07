import 'dart:async';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show SessionOrigin;
import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../cli/agent_marks.dart';
import '../../remote/remote_state.dart';
import '../../remote/ssh_reconnector.dart';
import '../../terminal/pane_layout.dart';
import '../../terminal/terminal_appearance.dart';
import '../../terminal/terminal_style.dart';
import '../../config/config_controller.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'agent_chip.dart';
import 'attention_marks.dart' show AttentionRing;
import 'device_pixel_lines.dart';
import 'ime_compose_reset.dart';
import 'remote_marks.dart';
import 'remote_strip.dart';
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart' show DriverPill, ShellxScrollbar, kPhoneIcon;
import 'terminal_shortcuts.dart';

/// One tab's panes (A3 P1, UI-A3 §2). A one-pane tab is exactly A4's single
/// terminal: no header, outline or divider, the same label and ring rect
/// (criterion 13).
class PaneTreeView extends ConsumerStatefulWidget {
  const PaneTreeView({
    super.key,
    required this.tab,
    required this.selected,
    required this.terminalFocus,
    required this.style,
    required this.shortcuts,
    this.onKeyEvent,
    required this.scrollFor,
    required this.onClosePane,
    this.ringed = const {},
    this.hiddenUnread = false,
    this.toastShowing = false,
  });

  final TerminalTab tab;

  /// The tab is the selected one: its focused pane gets [terminalFocus].
  final bool selected;
  final FocusNode terminalFocus;
  final TerminalStyle style;
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// A key reaching a pane's terminal before xterm sees it (key sequences).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final ScrollController Function(int sessionId) scrollFor;
  final void Function(int sessionId) onClosePane;

  /// Panes drawn with A4's ring (D18).
  final Set<int> ringed;

  /// A pane hidden by the zoom has unread notifications (D18).
  final bool hiddenUnread;

  /// The toast owns the bottom of the area: driver pills stay on top.
  final bool toastShowing;

  @override
  ConsumerState<PaneTreeView> createState() => _PaneTreeViewState();
}

class _PaneTreeViewState extends ConsumerState<PaneTreeView> {
  /// One key per pane, so a pane's TerminalView keeps its state (scroll,
  /// focus, IME, its laid-out grid) when a split or a zoom moves it into
  /// another subtree: it is moved, never mounted again.
  final _keys = <int, GlobalKey>{};

  GlobalKey _keyFor(int id) => _keys.putIfAbsent(id, GlobalKey.new);

  TerminalTabs get _tabs => ref.read(terminalTabsProvider.notifier);

  StreamSubscription<PaneReplacement>? _replacements;

  @override
  void initState() {
    super.initState();
    // A8 D22: a reconnect gives the pane a new session id; its TerminalView
    // is moved to it, not mounted again (scroll, IME and focus stay).
    _replacements = _tabs.paneReplacements.listen((r) {
      final key = _keys.remove(r.from);
      if (key != null) _keys[r.to] = key;
    });
  }

  @override
  void dispose() {
    unawaited(_replacements?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The pane headers' tooltips follow a reload (A9 D29).
    ref.watch(shellxConfigProvider.select((s) => s.bindings));
    final tab = widget.tab;
    _keys.removeWhere((id, _) => !tab.panes.containsKey(id));
    if (!tab.isSplit) return _pane(tab.focusedPaneId);
    final zoomed = tab.zoomedPaneId;
    final tree = _node(tab.layout, '', hide: zoomed);
    if (zoomed == null) return tree;
    // D10: the other panes keep their tree rectangles (so their grids stay
    // right) but are neither painted nor hit-tested nor sized to sessions.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(child: tree),
        _pane(zoomed),
      ],
    );
  }

  Widget _node(PaneNode node, PanePath path, {int? hide}) => switch (node) {
    PaneLeaf(:final sessionId) =>
      sessionId == hide ? const SizedBox.expand() : _pane(sessionId),
    final PaneSplit s => _SplitBox(
      // The axis is part of the key (final ruling m-3): when a close hands
      // this path to a split across, the divider (and a drag on it) goes
      // with the old split instead of carrying on with the new one.
      key: ValueKey('split.$path.${s.axis.name}'),
      split: s,
      path: path,
      onRatio: (ratio) =>
          _tabs.setRatio(widget.tab.id, path, ratio, axis: s.axis),
      onEqualize: () => _tabs.equalizeAt(widget.tab.id, path),
      first: _node(s.first, '${path}0', hide: hide),
      second: _node(s.second, '${path}1', hide: hide),
    ),
  };

  /// A7 D27: the command line acted on this pane in the last 10 s. Only
  /// this pane's mark is watched (ruling M7).
  bool _agent(int id) => ref.watch(
    agentMarksProvider.select(
      (m) => m.paneActive(id, ref.read(agentMarksClockProvider)()),
    ),
  );

  Widget _pane(int id) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final pane = tab.panes[id]!;
    final split = tab.isSplit;
    final focused = id == tab.focusedPaneId;
    final ringed = widget.ringed.contains(id);
    final scaler = MediaQuery.textScalerOf(context);
    final headerHeight = split ? ShellxSizes.paneHeaderFor(scaler) : 0.0;
    final appearance = ref.watch(terminalAppearanceProvider);
    // One widget shape for one pane and for many (only properties
    // differ), so the first split and the close back to one pane keep
    // this pane's TerminalView: same state, no remount, no resize.
    final terminal = Semantics(
      // One pane: A1/A4's label on the terminal itself, as before A3.
      container: !split,
      label: split
          ? null
          : ringed
          ? l10n.terminalPaneUnreadLabel(tab.label) +
                remoteSemantics(l10n, pane)
          : l10n.terminalPaneLabel(tab.label) + remoteSemantics(l10n, pane),
      child: PaneTerminal(
        pane: pane,
        scrollController: widget.scrollFor(id),
        focusNode: widget.selected && focused ? widget.terminalFocus : null,
        style: widget.style,
        theme: appearance.theme,
        cursorType: appearance.cursor,
        padding: appearance.padding,
        shortcuts: widget.shortcuts,
        onKeyEvent: widget.onKeyEvent,
        onMenu: (at) => _menu(id, at),
      ),
    );
    final phoneDrives = !pane.exited && pane.driver == DriverSide.phone;
    final body = LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (split) _header(id, pane, focused: focused, ringed: ringed),
                // Keyed: the header coming or going never rebuilds it.
                Expanded(key: const ValueKey('pane.terminal'), child: terminal),
              ],
            ),
          ),
          // UI-A3 §2.5 layers: terminal < focus outline < ring < pill.
          // Final ruling S-2: a hairline on whole device pixels.
          if (split && focused && tab.zoomedPaneId == null)
            Positioned.fill(
              child: DevicePixelOutline(
                key: const Key('pane.focusOutline'),
                // A9 D15: readable on the theme's background.
                color: appearance.focusOutline,
                devicePixelRatio: View.of(context).devicePixelRatio,
              ),
            ),
          // UI-A3 §2.5: A4's ring, around the pane (one pane: A4's rect).
          // Final ruling S-3: an unfocused pane's ring sits inside it, so
          // it never merges with the focused neighbour's outline.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(
                split && !focused ? ShellxSizes.paneRingInset : 0,
              ),
              child: AttentionRing(visible: ringed),
            ),
          ),
          // UI §2.5 (ruling S-2), in the pane under its header: top-right,
          // clear of where people read; when the cursor (the prompt line)
          // is under that corner it moves to the bottom-right.
          Positioned(
            top: headerHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ShellxSpace.s8,
                horizontal: ShellxSpace.s12,
              ),
              child: DriverPillSlot(
                terminal: pane.terminal,
                cellHeight: measureTerminalCell(widget.style, scaler).height,
                topPadding: appearance.padding.top,
                // The toast owns the bottom while it shows.
                canMoveDown: !widget.toastShowing,
                child: AnimatedSwitcher(
                  duration: ShellxMotion.of(context, ShellxMotion.base),
                  reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
                  switchInCurve: ShellxMotion.baseCurve,
                  switchOutCurve: ShellxMotion.exitCurve,
                  child: phoneDrives
                      ? DriverPill(
                          compact:
                              constraints.maxWidth <
                              ShellxSizes.pillCompactBelow,
                          iconOnly:
                              constraints.maxWidth <
                              ShellxSizes.pillIconOnlyBelow,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          // UI-A8 §3.2: over the terminal's bottom edge, no layout change.
          if (pane.canReconnect)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RemoteStrip(pane: pane),
            ),
        ],
      ),
    );
    final number = tab.paneNumber(id);
    return KeyedSubtree(
      key: _keyFor(id),
      child: Listener(
        onPointerDown: (_) => _pointerDown(id),
        child: Semantics(
          // Many panes: one region per pane (UI-A3 §8), header included.
          container: split,
          label: !split
              ? null
              : [
                      ringed
                          ? l10n.paneRegionUnreadLabel(
                              number,
                              tab.paneCount,
                              pane.automaticLabel,
                            )
                          : l10n.paneRegionLabel(
                              number,
                              tab.paneCount,
                              pane.automaticLabel,
                            ),
                      if (_agent(id)) l10n.agentChipTooltip,
                    ].join(', ') +
                    remoteSemantics(l10n, pane),
          // UI-A3 §8: what the header's mouse targets do.
          customSemanticsActions: !split
              ? null
              : {
                  CustomSemanticsAction(label: l10n.paneClose): () =>
                      widget.onClosePane(id),
                  CustomSemanticsAction(
                    label: tab.zoomedPaneId == id
                        ? l10n.paneUnzoom
                        : l10n.paneZoom,
                  ): () =>
                      _toggleZoom(id),
                  CustomSemanticsAction(label: l10n.paneSplitRight): () =>
                      _split(id, SplitAxis.row),
                  CustomSemanticsAction(label: l10n.paneSplitDown): () =>
                      _split(id, SplitAxis.column),
                },
          child: body,
        ),
      ),
    );
  }

  /// Before xterm handles the press: the model focuses this pane, and the
  /// keyboard follows (D2, UI-A3 §6) — also from the header, which xterm
  /// never sees, and while another region (the sidebar) has the keyboard.
  void _pointerDown(int id) {
    final tab = widget.tab;
    if (!tab.isSplit) return; // A1: xterm focuses its own view.
    if (tab.focusedPaneId != id) _tabs.focusPane(id);
    if (!widget.selected) return;
    final focus = widget.terminalFocus;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && focus.context != null) focus.requestFocus();
      })
      ..ensureVisualUpdate();
  }

  Widget _header(
    int id,
    PaneSession pane, {
    required bool focused,
    required bool ringed,
  }) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final zoomed = tab.zoomedPaneId == id;
    return _PaneHeader(
      key: Key('pane.header.$id'),
      pane: pane,
      focused: focused,
      unread: ringed,
      zoomed: zoomed
          ? l10n.paneZoomedIndicator(tab.paneNumber(id), tab.paneCount)
          : null,
      hiddenUnread: zoomed && widget.hiddenUnread,
      closeTooltip: withShortcut(
        l10n.paneCloseTooltip,
        closePaneShortcutLabel(),
      ),
      agent: _agent(id),
      onClose: () => widget.onClosePane(id),
      onToggleZoom: () => _toggleZoom(id),
    );
  }

  /// Through the window's action when there is one (it also announces).
  void _toggleZoom(int id) {
    _tabs.focusPane(id);
    if (!_invoke(const TogglePaneZoomIntent())) _tabs.toggleZoom();
  }

  void _split(int id, SplitAxis axis) {
    _tabs.focusPane(id);
    if (!_invoke(SplitPaneIntent(axis))) _tabs.split(axis);
  }

  bool _invoke<T extends Intent>(T intent) {
    final action = Actions.maybeFind<T>(context, intent: intent);
    if (action == null || !action.isEnabled(intent)) return false;
    Actions.invoke(context, intent);
    return true;
  }

  /// A1 ruling I6 entries; the pane under the pointer is focused first
  /// (D21) so the window actions act on it.
  Future<void> _menu(int id, Offset at) async {
    _tabs.focusPane(id);
    final l10n = AppLocalizations.of(context);
    final pane = widget.tab.panes[id];
    if (pane == null) return;
    final lost = pane.canReconnect;
    final choice = await showShellxMenu<Object>(
      context: context,
      at: at,
      entries: [
        // UI-A8 §3.2: first for a pane whose connection ended.
        if (lost)
          ShellxMenuEntry<Object>(
            key: const Key('menu.reconnect'),
            value: _RemotePaneAction.reconnect,
            label: l10n.sshReconnectAction,
          ),
        ShellxMenuEntry<Object>(
          key: const Key('menu.copy'),
          dividerBefore: lost,
          value: const CopySelectionIntent(),
          label: l10n.terminalCopy,
          shortcut: copyShortcutLabel(),
          enabled: pane.selection.selection != null,
        ),
        ShellxMenuEntry(
          key: const Key('menu.paste'),
          value: const PasteClipboardIntent(),
          label: l10n.terminalPaste,
          shortcut: pasteShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.selectAll'),
          value: const SelectAllIntent(fromMenu: true),
          label: l10n.terminalSelectAll,
          shortcut: selectAllShortcutLabel(),
        ),
        // D21, UI-A3 §4.1: splits always; the pane entries with two panes.
        ShellxMenuEntry(
          key: const Key('menu.splitRight'),
          value: const SplitPaneIntent(SplitAxis.row),
          label: l10n.paneSplitRight,
          shortcut: splitRightShortcutLabel(),
          dividerBefore: true,
        ),
        ShellxMenuEntry(
          key: const Key('menu.splitDown'),
          value: const SplitPaneIntent(SplitAxis.column),
          label: l10n.paneSplitDown,
          shortcut: splitDownShortcutLabel(),
        ),
        // A8 D24: a shell on this computer, next to the server's.
        if (pane.remote != null)
          ShellxMenuEntry<Object>(
            key: const Key('menu.splitLocalRight'),
            value: _RemotePaneAction.splitLocalRight,
            label: l10n.paneSplitLocalRight,
          ),
        if (widget.tab.isSplit) ...[
          ShellxMenuEntry(
            key: const Key('menu.zoomPane'),
            value: const TogglePaneZoomIntent(),
            label: widget.tab.zoomedPaneId == null
                ? l10n.paneZoom
                : l10n.paneUnzoom,
            shortcut: zoomPaneShortcutLabel(),
          ),
          ShellxMenuEntry(
            key: const Key('menu.equalize'),
            value: const EqualizePanesIntent(),
            label: l10n.paneEqualize,
            shortcut: equalizePanesShortcutLabel(),
          ),
          ShellxMenuEntry(
            key: const Key('menu.closePane'),
            // ⌘W's action closes the focused pane of a split tab; the menu
            // focused this pane first.
            value: const CloseTabIntent(),
            label: l10n.paneClose,
            shortcut: closePaneShortcutLabel(),
            dividerBefore: true,
          ),
        ],
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _RemotePaneAction.reconnect:
        unawaited(ref.read(sshReconnectorProvider.notifier).reconnectNow(id));
      case _RemotePaneAction.splitLocalRight:
        unawaited(_tabs.split(SplitAxis.row, local: true));
      case final Intent intent:
        Actions.maybeInvoke(context, intent);
    }
    widget.terminalFocus.requestFocus();
  }
}

/// A8: the menu items that are not window actions.
enum _RemotePaneAction { reconnect, splitLocalRight }

/// UI-A3 §2.2: the 1 px line, a 6 px hit area centred on it. Laid out by
/// [splitExtents], the function `TerminalTabs._clampForPixels` clamps
/// with: the first child `r·E` snapped to a device pixel, the line, the
/// rest. The line stays crisp, a pane at its clamp limit keeps its 20 × 5
/// cells, and each shared edge is computed once (no gap, no overlap).
class _SplitBox extends StatelessWidget {
  const _SplitBox({
    super.key,
    required this.split,
    required this.path,
    required this.onRatio,
    required this.onEqualize,
    required this.first,
    required this.second,
  });

  final PaneSplit split;
  final PanePath path;
  final ValueChanged<double> onRatio;
  final VoidCallback onEqualize;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final row = split.axis == SplitAxis.row;
      final extent = row ? c.maxWidth : c.maxHeight;
      const line = ShellxSizes.paneDivider;
      const hit = ShellxSizes.paneDividerHit;
      final (a, _) = splitExtents(
        extent,
        split.ratio,
        line,
        View.of(context).devicePixelRatio,
      );
      final hitStart = a + line / 2 - hit / 2;
      final divider = _PaneDivider(
        key: Key('pane.divider.$path'),
        path: path,
        axis: split.axis,
        ratio: split.ratio,
        start: a,
        extent: extent,
        onRatio: onRatio,
        onEqualize: onEqualize,
      );
      return Stack(
        children: row
            ? [
                Positioned(left: 0, top: 0, bottom: 0, width: a, child: first),
                Positioned(
                  left: a + line,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: second,
                ),
                Positioned(
                  left: hitStart,
                  top: 0,
                  bottom: 0,
                  width: hit,
                  child: divider,
                ),
              ]
            : [
                Positioned(left: 0, top: 0, right: 0, height: a, child: first),
                Positioned(
                  left: 0,
                  top: a + line,
                  right: 0,
                  bottom: 0,
                  child: second,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: hitStart,
                  height: hit,
                  child: divider,
                ),
              ],
      );
    },
  );
}

class _PaneDivider extends StatefulWidget {
  const _PaneDivider({
    super.key,
    required this.path,
    required this.axis,
    required this.ratio,
    required this.start,
    required this.extent,
    required this.onRatio,
    required this.onEqualize,
  });

  final PanePath path;
  final SplitAxis axis;
  final double ratio;

  /// Pixels of the first child: where the line starts.
  final double start;
  final double extent;
  final ValueChanged<double> onRatio;
  final VoidCallback onEqualize;

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovered = false;

  /// Where the line was when the drag began, and how far the pointer went
  /// since: the line follows the pointer from where it was grabbed (no
  /// jump of up to half the hit area), and comes back with it after a
  /// clamp.
  double? _from;
  double _moved = 0;

  bool get _row => widget.axis == SplitAxis.row;

  /// [ShellxSizes.paneDividerActive] hairlines (3 px at 1× and 2×; 3
  /// device pixels, 2.4 px, at 1.25×).
  static int _activePixels(double dpr) =>
      ShellxSizes.paneDividerActive.round() * hairlineDevicePixels(dpr);

  void _step(double delta) => widget.onRatio(widget.ratio + delta);

  static String _percent(double ratio) =>
      '${(ratio.clamp(0.0, 1.0) * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = _hovered || _from != null;
    final dpr = View.of(context).devicePixelRatio;
    final hairline = hairlineDevicePixels(dpr);
    return Semantics(
      slider: true,
      label: l10n.paneDividerLabel,
      value: _percent(widget.ratio),
      // What a step would show before the pixel clamp (the model's).
      increasedValue: _percent(widget.ratio + ShellxSizes.paneResizeStep),
      decreasedValue: _percent(widget.ratio - ShellxSizes.paneResizeStep),
      onIncrease: () => _step(ShellxSizes.paneResizeStep),
      onDecrease: () => _step(-ShellxSizes.paneResizeStep),
      child: MouseRegion(
        cursor: _row
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The movement inside the slop counts too: the line stays under
          // the pointer.
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => setState(() {
            _from = widget.start;
            _moved = 0;
          }),
          onPanUpdate: (d) {
            final from = _from;
            if (from == null || widget.extent <= 0) return;
            _moved += _row ? d.delta.dx : d.delta.dy;
            widget.onRatio((from + _moved) / widget.extent);
          },
          onPanEnd: (_) => setState(() => _from = null),
          onPanCancel: () => setState(() => _from = null),
          onDoubleTap: widget.onEqualize,
          // Final rulings S-1, S-2: on whole device pixels; a wider
          // accent band while active, so the cue shows next to a focus
          // outline of the same colour. The layout line stays 1 px.
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: active
                  ? ShellxDesktopColors.accent
                  : ShellxDesktopColors.line,
            ),
            duration: ShellxMotion.of(context, ShellxMotion.fast),
            builder: (context, color, _) => DevicePixelLine(
              key: Key('pane.dividerLine.${widget.path}'),
              vertical: _row,
              color: color ?? ShellxDesktopColors.line,
              devicePixels: active ? _activePixels(dpr) : hairline,
              devicePixelRatio: dpr,
            ),
          ),
        ),
      ),
    );
  }
}

/// UI-A3 §2.1: 22 px (taller with large text), only when a tab has panes.
/// `|8|● in 12|6| title |4|📱|4|👁|4|•|4|Zoomed · 2/3|4|× 18|4|`.
class _PaneHeader extends StatefulWidget {
  const _PaneHeader({
    super.key,
    required this.pane,
    required this.focused,
    required this.unread,
    required this.zoomed,
    required this.hiddenUnread,
    required this.closeTooltip,
    required this.agent,
    required this.onClose,
    required this.onToggleZoom,
  });

  final PaneSession pane;
  final bool focused;
  final bool unread;

  /// "Zoomed · 2/3" while this pane is zoomed.
  final String? zoomed;
  final bool hiddenUnread;
  final String closeTooltip;

  /// A7 D27: the "Agent" chip, before ×.
  final bool agent;
  final VoidCallback onClose;
  final VoidCallback onToggleZoom;

  @override
  State<_PaneHeader> createState() => _PaneHeaderState();
}

class _PaneHeaderState extends State<_PaneHeader> {
  bool _hovered = false;

  /// Half of what the × hit area adds around its 18 px visual: the gaps
  /// of the anatomy are measured to the visual.
  static const double _closeInset =
      (ShellxSizes.paneHeader - ShellxSizes.paneHeaderClose) / 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = widget.pane;
    final focused = widget.focused;
    final scaler = MediaQuery.textScalerOf(context);
    final height = ShellxSizes.paneHeaderFor(scaler);
    final driving = pane.driver == DriverSide.phone;
    final dot = pane.exited
        ? ShellxDesktopColors.err
        : pane.runningCommand
        ? ShellxDesktopColors.accent
        : ShellxDesktopColors.ok;
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) widget.onClose();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: ExcludeSemantics(
          child: Container(
            height: height,
            color: focused
                ? ShellxDesktopColors.rowSelected
                : _hovered
                ? ShellxDesktopColors.rowHover
                : ShellxDesktopColors.bgSidebar,
            child: Row(
              children: [
                // The double-click target is everything but the indicator
                // and the ×, so their single clicks act at once.
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: widget.onToggleZoom,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: ShellxSizes.paneHeaderPadH,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            child: Center(
                              child: pane.remoteState == RemoteState.connecting
                                  ? const ConnectingDot(
                                      box: ShellxSizes.paneHeaderDot,
                                    )
                                  : Container(
                                      width: ShellxSizes.paneHeaderDot,
                                      height: ShellxSizes.paneHeaderDot,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: pane.exited ? null : dot,
                                        border: pane.exited
                                            ? Border.all(color: dot, width: 1.5)
                                            : null,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: ShellxSpace.s6),
                          // UI-A8 §3.1: the SSH/tmux mark before the title.
                          if (pane.remote != null) ...[
                            RemoteMark(pane),
                            const SizedBox(width: ShellxSpace.s4),
                          ],
                          Expanded(
                            child: Text(
                              pane.automaticLabel,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: ShellxText.small.copyWith(
                                color: focused && !pane.exited
                                    ? ShellxDesktopColors.textPrimary
                                    : ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          ),
                          if (pane.origin == SessionOrigin.phone) ...[
                            const SizedBox(width: ShellxSpace.s4),
                            Tooltip(
                              message: l10n.sidebarPhoneOrigin,
                              excludeFromSemantics: true,
                              child: const Icon(
                                kPhoneIcon,
                                size: 12,
                                color: ShellxDesktopColors.textSecondary,
                              ),
                            ),
                          ],
                          if (pane.phoneAttached) ...[
                            const SizedBox(width: ShellxSpace.s4),
                            Tooltip(
                              message: driving
                                  ? l10n.sidebarPhoneDriving
                                  : l10n.sidebarPhoneViewing,
                              excludeFromSemantics: true,
                              child: Icon(
                                Icons.visibility_outlined,
                                size: 12,
                                color: driving
                                    ? ShellxDesktopColors.warn
                                    : ShellxDesktopColors.accent,
                              ),
                            ),
                          ],
                          if (widget.unread) ...[
                            const SizedBox(width: ShellxSpace.s4),
                            const _Dot(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.zoomed case final zoomed?) ...[
                  const SizedBox(width: ShellxSpace.s4),
                  // Final N-5: it looks like the button it is.
                  Tooltip(
                    message: l10n.paneUnzoom,
                    excludeFromSemantics: true,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        key: const Key('pane.zoomed'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onToggleZoom,
                        child: SizedBox(
                          height: height,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.hiddenUnread) ...[
                                const _Dot(key: Key('pane.zoom.unread')),
                                const SizedBox(width: ShellxSpace.s4),
                              ],
                              Text(
                                zoomed,
                                maxLines: 1,
                                softWrap: false,
                                style: ShellxText.caption.copyWith(
                                  color: ShellxDesktopColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.agent) ...[
                  const SizedBox(width: ShellxSpace.s4),
                  const AgentChip(large: true),
                ],
                const SizedBox(width: ShellxSpace.s4 - _closeInset),
                // The place stays when hidden: the title never jumps.
                Visibility(
                  visible: focused || _hovered,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Tooltip(
                    message: widget.closeTooltip,
                    excludeFromSemantics: true,
                    child: _HeaderClose(
                      key: Key('pane.close.${pane.id}'),
                      onPressed: widget.onClose,
                    ),
                  ),
                ),
                // 4 px to the whole 22 px target (not to its 18 px
                // visual): the divider's 2.5 px overhang never covers it.
                const SizedBox(width: ShellxSpace.s4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: ShellxSizes.paneHeaderDot,
    height: ShellxSizes.paneHeaderDot,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: ShellxDesktopColors.accent,
    ),
  );
}

/// 18 px visual (`r4`), 22 × 22 hit, glyph 12 (UI-A3 §1.2).
class _HeaderClose extends StatefulWidget {
  const _HeaderClose({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_HeaderClose> createState() => _HeaderCloseState();
}

class _HeaderCloseState extends State<_HeaderClose> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      child: SizedBox.square(
        dimension: ShellxSizes.paneHeader,
        child: Center(
          child: Container(
            width: ShellxSizes.paneHeaderClose,
            height: ShellxSizes.paneHeaderClose,
            decoration: BoxDecoration(
              color: _hovered ? ShellxDesktopColors.rowPressed : null,
              borderRadius: BorderRadius.circular(ShellxRadius.r4),
            ),
            child: Icon(
              Icons.close,
              size: 12,
              color: _hovered
                  ? ShellxDesktopColors.textPrimary
                  : ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// One pane's terminal with its overlay scrollbar (UI §2.3). The label is
/// the pane's (or, with one pane, A1's "Terminal {title}").
class PaneTerminal extends StatelessWidget {
  const PaneTerminal({
    super.key,
    required this.pane,
    required this.scrollController,
    required this.focusNode,
    required this.style,
    required this.theme,
    required this.cursorType,
    required this.padding,
    required this.shortcuts,
    this.onKeyEvent,
    required this.onMenu,
  });

  final PaneSession pane;
  final ScrollController scrollController;
  final FocusNode? focusNode;
  final TerminalStyle style;

  /// A9 D13-D16, D18 (`terminalAppearanceProvider`).
  final TerminalTheme theme;
  final TerminalCursorType cursorType;
  final EdgeInsets padding;
  final Map<ShortcutActivator, Intent>? shortcuts;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final void Function(Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) => ClipRect(
    // A buffer scrolled by part of a row paints that row outside the
    // view; the clip keeps it off the signed-out strip and pane header.
    child: ShellxScrollbar(
      controller: scrollController,
      child: ImeComposeReset(
        child: TerminalView(
          pane.terminal,
          controller: pane.selection,
          scrollController: scrollController,
          focusNode: focusNode,
          autofocus: focusNode != null,
          theme: theme,
          textStyle: style,
          cursorType: cursorType,
          padding: padding,
          shortcuts: shortcuts,
          onKeyEvent: onKeyEvent == null
              ? null
              : (_, event) => onKeyEvent!(event),
          // Only when the program did not take the mouse (xterm reports
          // the click to it first): vim or htop with mouse mode keep it.
          onSecondaryTapUp: (details, _) => onMenu(details.globalPosition),
        ),
      ),
    ),
  );
}

/// Puts the driver pill top-right, or bottom-right while the cursor is on
/// the rows the top corner covers (a fresh prompt is on the first row).
/// Follows the terminal as it writes, rebuilding only when the corner
/// changes.
class DriverPillSlot extends StatefulWidget {
  const DriverPillSlot({
    super.key,
    required this.terminal,
    required this.cellHeight,
    required this.topPadding,
    required this.canMoveDown,
    required this.child,
  });

  final Terminal terminal;
  final double cellHeight;

  /// The terminal's own top padding (A9 D18).
  final double topPadding;
  final bool canMoveDown;
  final Widget child;

  @override
  State<DriverPillSlot> createState() => _DriverPillSlotState();
}

class _DriverPillSlotState extends State<DriverPillSlot> {
  /// The pill's laid-out height (final ruling S-4: a wrapped pill is two
  /// lines); never less than one line, so a pill that is just appearing
  /// does not start in a corner it covers.
  double _pillHeight = ShellxSizes.driverPill;
  late bool _down = _cursorUnderCorner();

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_onTerminal);
  }

  @override
  void didUpdateWidget(DriverPillSlot old) {
    super.didUpdateWidget(old);
    if (!identical(old.terminal, widget.terminal)) {
      old.terminal.removeListener(_onTerminal);
      widget.terminal.addListener(_onTerminal);
    }
    _down = _cursorUnderCorner();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminal);
    super.dispose();
  }

  /// The rows under the pill's corner: its 8 px inset and its height,
  /// past the terminal's own top padding.
  bool _cursorUnderCorner() {
    final cell = widget.cellHeight;
    if (cell <= 0) return false;
    final covered = ((ShellxSpace.s8 + _pillHeight - widget.topPadding) / cell)
        .ceil();
    return widget.terminal.buffer.cursorY < covered;
  }

  void _onPillSize(Size size) {
    final height = size.height < ShellxSizes.driverPill
        ? ShellxSizes.driverPill
        : size.height;
    if (!mounted || height == _pillHeight) return;
    setState(() {
      _pillHeight = height;
      _down = _cursorUnderCorner();
    });
  }

  void _onTerminal() {
    final down = _cursorUnderCorner();
    if (down != _down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: _down && widget.canMoveDown
        ? Alignment.bottomRight
        : Alignment.topRight,
    child: _SizeReport(onSize: _onPillSize, child: widget.child),
  );
}

/// Tells [onSize] its child's size after a layout that changed it (in a
/// post-frame callback: never a rebuild during layout).
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport render) =>
      render.onSize = onSize;
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);
  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reported) return;
    final now = _reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(now));
  }
}

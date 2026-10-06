import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/context_line.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'inline_name_field.dart';
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

/// UI §3.1 context menu ("Đóng tab  ⌘W") at [at] (global). Secondary
/// click, Shift+F10 and the Menu key open it.
Future<void> showTabContextMenu({
  required BuildContext context,
  required Offset at,
  required VoidCallback onClose,
}) async {
  final l10n = AppLocalizations.of(context);
  final choice = await showShellxMenu<_TabMenuChoice>(
    context: context,
    at: at,
    entries: [
      ShellxMenuEntry(
        key: const Key('menu.closeTab'),
        value: _TabMenuChoice.close,
        label: l10n.terminalCloseTab,
        shortcut: closeTabShortcutLabel(),
      ),
    ],
  );
  if (choice == _TabMenuChoice.close) onClose();
}

enum _TabMenuChoice { close }

/// One sidebar row (UI §2.2 anatomy, §3.1 states, §3.7 semantics; UI-A2
/// §2 context line, §4 inline name, §8 semantics).
class SessionTabRow extends StatefulWidget {
  const SessionTabRow({
    super.key,
    required this.tab,
    required this.selected,
    required this.position,
    required this.count,
    required this.onSelect,
    required this.onClose,
    this.focused = false,
    this.renaming = false,
    this.onStartRename,
    this.onRename,
    this.onCancelRename,
    this.onOpenPort,
    this.onMenu,
    this.positionLabel,
    this.extraActions = const {},
    this.home = '',
  });

  final TerminalTab tab;
  final bool selected;

  /// 1-based place in the list, for the "tab 2 of 4" semantics.
  final int position;
  final int count;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  /// The list has keyboard focus and this is its current row: draw the
  /// focus ring (UI §3, keyboard focus only).
  final bool focused;

  /// UI-A2 §4: the name field replaces the title.
  final bool renaming;

  /// The second click of a double-click (UI-A2 §4).
  final VoidCallback? onStartRename;
  final void Function(String text)? onRename;
  final VoidCallback? onCancelRename;

  /// UI-A2 §2.4: a port link was clicked.
  final void Function(int port)? onOpenPort;

  /// The sidebar's row menu (UI-A2 §5.1) at a global position; null: the
  /// A1 menu.
  final void Function(Offset at)? onMenu;

  /// Replaces "tab i of n" (UI-A2 §8: "… in `workspace`").
  final String? positionLabel;

  /// More custom semantics actions (rename, move, ports — UI-A2 §8).
  final Map<CustomSemanticsAction, VoidCallback> extraActions;

  /// The user's home, for `~` (UI-A2 §2.3).
  final String home;

  /// UI-A1 §1.3 / UI-A2 §1.3: max(30, 18·s + 12); with a context line
  /// max(46, 18·s + 14·s + 14). The sidebar sums them to scroll a row it
  /// has not built yet into view.
  static double heightFor(TextScaler textScaler, {bool context = false}) =>
      context
      ? max(
          ShellxSizes.rowWithContext,
          textScaler.scale(ShellxSizes.rowTextLine) +
              textScaler.scale(ShellxSizes.contextLine) +
              2 * ShellxSizes.rowContextPadding +
              ShellxSizes.contextGap,
        )
      : max(
          ShellxSizes.row,
          textScaler.scale(ShellxSizes.rowTextLine) +
              ShellxSizes.rowTextPadding,
        );

  @override
  State<SessionTabRow> createState() => SessionTabRowState();
}

class SessionTabRowState extends State<SessionTabRow> {
  bool _hover = false;
  bool _pressed = false;

  /// Selection changes are instant (UI §1.5); only hover/pressed fade.
  bool _instant = true;

  /// The first click of a possible double-click. A plain `onDoubleTap`
  /// would hold every single click for the double-tap timeout, and A1
  /// switches tabs on the click itself.
  DateTime? _lastTap;
  Offset? _lastTapAt;

  /// Where the pointer went down for the click being handled.
  Offset? _downAt;

  @override
  void didUpdateWidget(SessionTabRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _instant = oldWidget.selected != widget.selected;
    if (widget.renaming && !oldWidget.renaming) {
      // UI-A2 §2.5: no hover/pressed look while the name field is open.
      _hover = false;
      _pressed = false;
      _lastTap = null;
      _lastTapAt = null;
    }
  }

  /// UI §3.7 + UI-A2 §8: title · status · [branch] · [folder] · [ports] ·
  /// [origin] · [viewing/driving] · position.
  String _semanticsLabel(AppLocalizations l10n) {
    final tab = widget.tab;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final parts = <String>[
      tab.label,
      if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
      else if (tab.runningCommand)
        l10n.sidebarStatusRunning
      else
        l10n.sidebarStatusIdle,
      if (tab.gitBranch case final branch?) l10n.sidebarBranch(branch),
      if (tab.cwd case final cwd?)
        l10n.sidebarFolder(
          displayPath(cwd, home: widget.home, windows: windows),
        ),
      if (tab.ports.isNotEmpty)
        l10n.sidebarPorts(tab.ports.length, _sortedPorts(tab).join(', ')),
      if (tab.origin == SessionOrigin.phone) l10n.sidebarPhoneOriginSemantics,
      if (tab.phoneAttached)
        tab.driver == DriverSide.phone
            ? l10n.sidebarPhoneDrivingSemantics
            : l10n.sidebarPhoneViewingSemantics,
      widget.positionLabel ??
          l10n.sidebarPosition(widget.position, widget.count),
    ];
    return parts.join(', ');
  }

  /// Shift+F10 / Menu key (from the sidebar): the menu under the row's
  /// left edge.
  void openMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _menu(box.localToGlobal(Offset(ShellxSpace.s8, box.size.height)));
  }

  void _menu(Offset at) {
    final custom = widget.onMenu;
    if (custom != null) {
      custom(at);
    } else {
      showTabContextMenu(context: context, at: at, onClose: widget.onClose);
    }
  }

  /// A click selects at once; a second click within the double-tap
  /// timeout opens the name field instead (the first one already
  /// selected the row).
  void _onTap() {
    final now = DateTime.now();
    final at = _downAt;
    final last = _lastTap;
    final lastAt = _lastTapAt;
    final rename = widget.onStartRename;
    // Same rules as Flutter's double-tap: within the timeout and within
    // kDoubleTapSlop of the first click.
    if (rename != null &&
        last != null &&
        now.difference(last) < kDoubleTapTimeout &&
        (at == null ||
            lastAt == null ||
            (at - lastAt).distance < kDoubleTapSlop)) {
      _lastTap = null;
      _lastTapAt = null;
      rename();
      return;
    }
    _lastTap = now;
    _lastTapAt = at;
    widget.onSelect();
  }

  void _setHover(bool value) {
    if (_hover == value || widget.renaming) return;
    setState(() {
      _hover = value;
      _instant = false;
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value || (value && widget.renaming)) return;
    setState(() {
      _pressed = value;
      _instant = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final renaming = widget.renaming;
    final scaler = MediaQuery.textScalerOf(context);
    final withContext = tab.hasContext;
    final height = SessionTabRow.heightFor(scaler, context: withContext);
    final background = _pressed
        ? ShellxDesktopColors.rowPressed
        : widget.selected
        ? ShellxDesktopColors.rowSelected
        : _hover
        ? ShellxDesktopColors.rowHover
        : Colors.transparent;
    final titleStyle =
        (widget.selected ? ShellxText.bodyStrong : ShellxText.body).copyWith(
          color: tab.exited
              ? ShellxDesktopColors.textSecondary
              : widget.selected
              ? ShellxDesktopColors.textTitle
              : ShellxDesktopColors.textPrimary,
        );
    final driving = tab.driver == DriverSide.phone;
    // UI §2.2: the close button shows on hover and on the selected row;
    // its slot is always kept, so a title never re-truncates on hover.
    // UI-A2 §2.5: hidden while the name field is open.
    final showClose = !renaming && (_hover || widget.selected);
    final shortcut = closeTabShortcutLabel();

    const rowPadding = EdgeInsets.only(
      left: ShellxSpace.s8,
      // 8 px to the close button's 20 px visual.
      right:
          ShellxSpace.s8 -
          (ShellxSizes.rowCloseHit - ShellxSizes.rowCloseVisual) / 2,
    );
    final titleLine = scaler.scale(ShellxSizes.rowTextLine);
    final titleBox = max(titleLine, ShellxSizes.rowCloseHit);
    final contextLine = scaler.scale(ShellxSizes.contextLine);
    final contextBox = max(contextLine, ShellxSizes.portHit);
    // The 24 px title box (×) and the 24 px context box (ports) overlap
    // by 6 px in a 46 px row. Where a shown × sits, it wins that strip
    // whole (its 20 px glyph reaches y 25); left of the ×'s column the
    // ports keep their full 24 px.
    final titleTop =
        ShellxSizes.rowContextPadding + titleLine / 2 - titleBox / 2;
    final contextTop =
        ShellxSizes.rowContextPadding +
        titleLine +
        ShellxSizes.contextGap -
        (contextBox - contextLine) / 2;
    final overlap = max(0.0, titleTop + titleBox - contextTop);

    final titleRow = Row(
      children: [
        SizedBox(
          width: ShellxSizes.dotSlot,
          child: Center(child: _Dot(tab)),
        ),
        const SizedBox(width: ShellxSpace.s8),
        Expanded(
          child: renaming
              ? InlineNameField(
                  initial: tab.label,
                  style: ShellxText.body,
                  label: l10n.tabNameField,
                  identity: ('tab', tab.id),
                  onCommit: (text) => widget.onRename?.call(text),
                  onCancel: () => widget.onCancelRename?.call(),
                )
              : _Title(tab.label, titleStyle),
        ),
        if (tab.origin == SessionOrigin.phone) ...[
          const SizedBox(width: ShellxSpace.s4),
          Tooltip(
            message: l10n.sidebarPhoneOrigin,
            excludeFromSemantics: true,
            child: const Icon(
              kPhoneIcon,
              size: ShellxSizes.mark,
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ],
        if (tab.phoneAttached) ...[
          const SizedBox(width: ShellxSpace.s4),
          Tooltip(
            message: driving
                ? l10n.sidebarPhoneDriving
                : l10n.sidebarPhoneViewing,
            excludeFromSemantics: true,
            child: Icon(
              Icons.visibility_outlined,
              size: ShellxSizes.mark,
              color: driving
                  ? ShellxDesktopColors.warn
                  : ShellxDesktopColors.accent,
            ),
          ),
        ],
        const SizedBox(width: ShellxSpace.s4 - 2),
        Visibility(
          visible: showClose,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _RowCloseButton(
            tooltip: shortcutTooltip(
              l10n.terminalCloseTabTooltip(shortcut),
              shortcut,
            ),
            onPressed: widget.onClose,
          ),
        ),
      ],
    );

    return Semantics(
      button: !renaming,
      selected: widget.selected,
      label: _semanticsLabel(l10n),
      onTap: renaming ? null : widget.onSelect,
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.terminalCloseTab): widget.onClose,
        ...widget.extraActions,
      },
      // While renaming, the name field is the row's one child node
      // ("Tab name", UI-A2 §4).
      excludeSemantics: !renaming,
      child: Listener(
        // UI §3.1: a middle click closes, with the same rules as ⌘W.
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons & kMiddleMouseButton != 0) {
            widget.onClose();
          }
        },
        child: MouseRegion(
          onEnter: (_) => _setHover(true),
          onExit: (_) => _setHover(false),
          child: GestureDetector(
            // While renaming, clicks belong to the field (cursor, selection,
            // its own context menu).
            onTap: renaming ? null : _onTap,
            onTapDown: renaming
                ? null
                : (details) {
                    _downAt = details.globalPosition;
                    _setPressed(true);
                  },
            onTapUp: renaming ? null : (_) => _setPressed(false),
            onTapCancel: renaming ? null : () => _setPressed(false),
            onSecondaryTapUp: renaming
                ? null
                : (details) => _menu(details.globalPosition),
            child: AnimatedContainer(
              duration: _instant
                  ? Duration.zero
                  : ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
              ),
              child: DecoratedBox(
                // The keyboard ring switches at once (UI §1.5, §3): in
                // front, outside the hover fade. Never null: a decoration
                // that comes and goes would change the subtree and
                // rebuild an open name field.
                position: DecorationPosition.foreground,
                decoration: widget.focused
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(ShellxRadius.r6),
                        border: Border.all(
                          color: ShellxDesktopColors.accent,
                          width: ShellxSizes.focusRing,
                        ),
                      )
                    : const BoxDecoration(),
                child: Stack(
                  children: [
                    if (widget.selected)
                      Positioned(
                        // With the keyboard ring on the row's edge, the bar
                        // moves inside it so both stay visible (UI §3.1).
                        // UI-A2 §2.1: centred on the whole row, 46 included.
                        left: widget.focused
                            ? ShellxSizes.focusRing + ShellxSizes.selectedBarGap
                            : 0,
                        top: (height - ShellxSizes.selectedBarHeight) / 2,
                        child: Container(
                          key: const Key('row.selectedBar'),
                          width: ShellxSizes.selectedBarWidth,
                          height: ShellxSizes.selectedBarHeight,
                          decoration: BoxDecoration(
                            color: ShellxDesktopColors.accent,
                            borderRadius: BorderRadius.circular(
                              ShellxRadius.r4,
                            ),
                          ),
                        ),
                      ),
                    if (!withContext)
                      Padding(
                        padding: rowPadding,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [titleRow],
                        ),
                      )
                    else ...[
                      Positioned(
                        left: 0,
                        right: 0,
                        // The title line's centre stays 6 + line/2 from the
                        // top; the box is as tall as the 24 px close button.
                        top: titleTop,
                        height: titleBox,
                        child: Padding(padding: rowPadding, child: titleRow),
                      ),
                      Positioned(
                        left: ShellxSizes.contextInset,
                        right: ShellxSpace.s8,
                        // The 14 px line sits 2 below the title line; the
                        // box grows to the 24 px port hit area around it.
                        top: contextTop,
                        height: contextBox,
                        child: _HitBand(
                          // The ×'s column, measured from the line's right
                          // edge: the line ends 8 px in, the × hit area 6.
                          cornerWidth: showClose
                              ? ShellxSizes.rowCloseHit -
                                    (ShellxSpace.s8 - rowPadding.right)
                              : 0,
                          cornerHeight: overlap,
                          child: _ContextLine(
                            tab: tab,
                            home: widget.home,
                            onOpenPort: widget.onOpenPort,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Takes no hits in its top-right corner of [cornerWidth] × [cornerHeight]
/// (where the shown × of the title line reaches down); those fall through
/// to the × below it.
class _HitBand extends SingleChildRenderObjectWidget {
  const _HitBand({
    required this.cornerWidth,
    required this.cornerHeight,
    required super.child,
  });
  final double cornerWidth;
  final double cornerHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitBand(cornerWidth, cornerHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderHitBand renderObject) {
    renderObject
      ..cornerWidth = cornerWidth
      ..cornerHeight = cornerHeight;
  }
}

class _RenderHitBand extends RenderProxyBox {
  _RenderHitBand(this.cornerWidth, this.cornerHeight);
  double cornerWidth;
  double cornerHeight;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final inCorner =
        position.dx >= size.width - cornerWidth && position.dy < cornerHeight;
    return !inCorner && super.hitTest(result, position: position);
  }
}

/// The row's "×" (UI §2.2): 24 hit, 20 visual, `Icons.close` 14; hover
/// `rowPressed` + `textPrimary`. Not a tab stop (the list is one stop;
/// ⌘W and the row's menu close from the keyboard) and not in semantics
/// (the row's "Đóng tab" action is).
class _RowCloseButton extends StatefulWidget {
  const _RowCloseButton({required this.tooltip, required this.onPressed});
  final InlineSpan tooltip;
  final VoidCallback onPressed;

  @override
  State<_RowCloseButton> createState() => _RowCloseButtonState();
}

class _RowCloseButtonState extends State<_RowCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    richMessage: widget.tooltip,
    excludeFromSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        key: const Key('row.close'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: SizedBox.square(
          dimension: ShellxSizes.rowCloseHit,
          child: Center(
            child: AnimatedContainer(
              duration: ShellxMotion.of(context, ShellxMotion.fast),
              curve: ShellxMotion.fastCurve,
              width: ShellxSizes.rowCloseVisual,
              height: ShellxSizes.rowCloseVisual,
              decoration: BoxDecoration(
                color: _hover
                    ? ShellxDesktopColors.rowPressed
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(ShellxRadius.r4),
              ),
              child: Icon(
                Icons.close,
                size: ShellxSizes.rowCloseGlyph,
                color: _hover
                    ? ShellxDesktopColors.textPrimary
                    : ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One line, ellipsis; the full title as a tooltip only when it is cut
/// (UI §3.1 hover). The tooltip opens right of the sidebar, level with the
/// row, so it never covers the next tab (or its marks).
class _Title extends StatelessWidget {
  const _Title(this.text, this.style);
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final cut = painter.didExceedMaxLines;
      painter.dispose();
      if (!cut) return title;
      return Tooltip(
        message: text,
        excludeFromSemantics: true,
        constraints: const BoxConstraints(
          maxWidth: ShellxSizes.titleTooltipMaxWidth,
        ),
        positionDelegate: besideSidebar,
        child: title,
      );
    },
  );
}

/// Right of the sidebar ([ShellxSizes.sidebarWidth] + 6), vertically
/// centred on the row, kept inside the window.
Offset besideSidebar(TooltipPositionContext context) {
  final overlay = context.overlaySize;
  final size = context.tooltipSize;
  final double x = (ShellxSizes.sidebarWidth + ShellxSpace.s6).clamp(
    0.0,
    max(0.0, overlay.width - size.width - ShellxSpace.s8),
  );
  final double y = (context.target.dy - size.height / 2).clamp(
    0.0,
    max(0.0, overlay.height - size.height),
  );
  return Offset(x, y);
}

/// UI §3.1 status dot (8 px), three shapes so it never relies on colour
/// alone (WCAG 1.4.1): idle a filled `ok` dot; running a command an
/// `accent` ring with a 4 px centre (a target); exited non-zero a hollow
/// 1.5 px `err` ring. The meaning is also in the row's semantics label.
class _Dot extends StatelessWidget {
  const _Dot(this.tab);
  final TerminalTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab.exited) {
      return Container(
        key: const Key('dot.exited'),
        width: ShellxSizes.dot,
        height: ShellxSizes.dot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShellxDesktopColors.err,
            width: ShellxSizes.dotRing,
          ),
        ),
      );
    }
    if (tab.runningCommand) {
      return Container(
        key: const Key('dot.running'),
        width: ShellxSizes.dot,
        height: ShellxSizes.dot,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShellxDesktopColors.accent,
            width: ShellxSizes.dotRing,
          ),
        ),
        child: Container(
          width: ShellxSizes.dotCentre,
          height: ShellxSizes.dotCentre,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShellxDesktopColors.accent,
          ),
        ),
      );
    }
    return Container(
      key: const Key('dot.idle'),
      width: ShellxSizes.dot,
      height: ShellxSizes.dot,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ShellxDesktopColors.ok,
      ),
    );
  }
}

/// UI-A2 §2: branch · ~/path · :ports, laid out by [layoutContextLine].
class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.tab,
    required this.home,
    required this.onOpenPort,
  });

  final TerminalTab tab;
  final String home;
  final void Function(int port)? onOpenPort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final style = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final full = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final path = tab.cwd == null
        ? null
        : displayPath(tab.cwd!, home: home, windows: windows);
    return LayoutBuilder(
      key: const Key('row.contextLine'),
      builder: (context, constraints) {
        final widths = <String, double>{};
        double measure(String text) => widths.putIfAbsent(text, () {
          final painter = TextPainter(
            text: TextSpan(text: text, style: full),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        });
        final ports = _sortedPorts(tab);
        final layout = layoutContextLine(
          branch: tab.gitBranch,
          path: path,
          ports: ports,
          width: constraints.maxWidth,
          measure: measure,
          windows: windows,
        );
        Widget text(String s) =>
            Text(s, style: style, maxLines: 1, softWrap: false);
        final children = <Widget>[];
        void separator() {
          if (children.isNotEmpty) children.add(text(' · '));
        }

        if (layout.branch case final branch?) children.add(text(branch));
        if (layout.path case final p?) {
          separator();
          children.add(text(p));
        }
        if (layout.ports.isNotEmpty) {
          separator();
          for (final (i, port) in layout.ports.indexed) {
            if (i > 0) children.add(const SizedBox(width: ShellxSizes.portGap));
            children.add(
              _PortLink(
                port: port,
                live: !tab.exited && onOpenPort != null,
                onOpen: onOpenPort,
              ),
            );
          }
          if (layout.morePorts > 0) {
            children
              ..add(const SizedBox(width: ShellxSizes.portGap))
              ..add(
                Tooltip(
                  message: l10n.portsMoreTooltip(ports.join(', ')),
                  excludeFromSemantics: true,
                  positionDelegate: besideSidebar,
                  child: text('+${layout.morePorts}'),
                ),
              );
          }
        }
        Widget line = ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
        if (layout.truncated) {
          final whole = [
            ?tab.gitBranch,
            ?path,
            if (ports.isNotEmpty) ports.map((p) => ':$p').join(' '),
          ].join(' · ');
          line = Tooltip(
            message: whole,
            excludeFromSemantics: true,
            positionDelegate: besideSidebar,
            waitDuration: ShellxMotion.tooltipWait,
            constraints: const BoxConstraints(
              maxWidth: ShellxSizes.titleTooltipMaxWidth,
            ),
            child: line,
          );
        }
        return ExcludeSemantics(child: line);
      },
    );
  }
}

/// UI-A2 §2.4: `:3000` in `accent`, a 24 px hit area; hover: underline,
/// `rowPressed` fill (`r4`) and the click cursor; pressed: the fill. Plain
/// `textSecondary`, without any of that, once the tab exited.
class _PortLink extends StatefulWidget {
  const _PortLink({required this.port, required this.live, this.onOpen});
  final int port;
  final bool live;
  final void Function(int port)? onOpen;

  @override
  State<_PortLink> createState() => _PortLinkState();
}

class _PortLinkState extends State<_PortLink> {
  bool _hover = false;
  bool _pressed = false;

  void _set({bool? hover, bool? pressed}) => setState(() {
    _hover = hover ?? _hover;
    _pressed = pressed ?? _pressed;
  });

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final style = ShellxText.caption.copyWith(
      color: live
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      decoration: live && _hover ? TextDecoration.underline : null,
      decorationColor: ShellxDesktopColors.accent,
    );
    final box = AnimatedContainer(
      key: Key('port.${widget.port}'),
      duration: ShellxMotion.of(context, ShellxMotion.fast),
      curve: ShellxMotion.fastCurve,
      height: ShellxSizes.portHit,
      padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.portPadH),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live && (_hover || _pressed)
            ? ShellxDesktopColors.rowPressed
            : Colors.transparent,
        borderRadius: BorderRadius.circular(ShellxRadius.r4),
      ),
      child: Text(':${widget.port}', style: style, maxLines: 1),
    );
    if (!live) return box;
    return Tooltip(
      message: AppLocalizations.of(context).portOpenTooltip(widget.port),
      excludeFromSemantics: true,
      positionDelegate: besideSidebar,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _set(hover: true),
        onExit: (_) => _set(hover: false, pressed: false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Wins the arena over the row's tap: a port click never selects.
          onTapDown: (_) => _set(pressed: true),
          onTapUp: (_) => _set(pressed: false),
          onTapCancel: () => _set(pressed: false),
          onTap: () => widget.onOpen?.call(widget.port),
          child: box,
        ),
      ),
    );
  }
}

/// One order everywhere (line, tooltips, semantics): the smallest first.
List<int> _sortedPorts(TerminalTab tab) => [...tab.ports]..sort();

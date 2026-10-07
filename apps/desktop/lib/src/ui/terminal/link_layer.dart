import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart' show TerminalLinkKind;
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../terminal/link_finder.dart';
import '../../terminal/link_resolver.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';

/// A10 D7: how paths found in the terminal are checked and shown.
final linkResolverProvider = Provider<LinkResolver>(
  (ref) => LinkResolver(
    home: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    windows: Platform.isWindows,
  ),
);

/// Whether the key that opens links is down: ⌘ on macOS, Ctrl on Windows
/// (A10 D8).
bool get linkModifierDown => defaultTargetPlatform == TargetPlatform.macOS
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// A pane has local paths (not a server's, not a tmux on a server).
bool paneHasLocalPaths(PaneSession pane) => pane.remote?.launch.host == null;

/// The address shown in the question about an OSC 8 link: 200 characters at
/// most, the middle cut, so the host at the start and the tail both show.
String shortenAddress(String uri) => uri.length <= 200
    ? uri
    : '${uri.substring(0, 120)}…${uri.substring(uri.length - 79)}';

/// Opens or reveals [hit] (A10 D6, D7, D10). Never throws; a failure is a
/// toast.
Future<void> activateLink(
  WidgetRef ref,
  BuildContext context,
  LinkHit hit,
  PaneSession pane,
) async {
  final l10n = AppLocalizations.of(context);
  final opener = ref.read(desktopServicesProvider).urlOpener;
  final tabs = ref.read(terminalTabsProvider.notifier);
  final router = ref.read(windowRouterProvider.notifier);
  try {
    if (hit.kind == TerminalLinkKind.url) {
      if (hit.needsConfirm) {
        final ok = await router.confirm(
          ConfirmRequest(
            title: l10n.linkConfirmTitle,
            body: l10n.linkConfirmBody(shortenAddress(hit.target)),
            confirmLabel: l10n.linkConfirmAction,
            destructive: false,
          ),
        );
        if (!ok) return;
      }
      await opener.openWebLink(Uri.parse(hit.target));
    } else {
      final found = await ref
          .read(linkResolverProvider)
          .resolve(hit.target, cwd: pane.cwd);
      if (found == null) return;
      await opener.reveal(found.path, isDirectory: found.isDirectory);
    }
  } on Object catch (error) {
    debugPrint('ShellX: opening a link failed: ${error.runtimeType}');
    tabs.showNotice(const LinkOpenFailedNotice());
  }
}

typedef LinkViewBuilder =
    Widget Function(BuildContext context, MouseCursor cursor);

/// A10 D8: hover with ⌘ (Ctrl) held underlines the link under the pointer
/// and shows a hand; ⌘-click opens it. [builder] builds the TerminalView
/// with the cursor it must use. Plain clicks are untouched.
///
/// The click is read from a [Listener] (outside the gesture arena), not from
/// `TerminalView.onTapUp`: xterm 4.0.0 never calls that callback (its
/// gesture detector only forwards `onSingleTapUp`, which `TerminalView` does
/// not set).
class LinkLayer extends ConsumerStatefulWidget {
  const LinkLayer({
    super.key,
    required this.pane,
    required this.viewKey,
    required this.scrollController,
    required this.builder,
  });

  final PaneSession pane;
  final GlobalKey<TerminalViewState> viewKey;
  final ScrollController scrollController;
  final LinkViewBuilder builder;

  @override
  ConsumerState<LinkLayer> createState() => _LinkLayerState();
}

class _LinkLayerState extends ConsumerState<LinkLayer> {
  Offset? _pointer;
  Offset? _down;
  LinkHit? _hit;
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.metaLeft ||
        k == LogicalKeyboardKey.metaRight ||
        k == LogicalKeyboardKey.controlLeft ||
        k == LogicalKeyboardKey.controlRight) {
      // After the key state has been updated.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  }

  CellOffset? _cellAt(Offset local) =>
      widget.viewKey.currentState?.renderTerminal.getCellOffset(local);

  void _set(LinkHit? hit) {
    if (hit == null && _hit == null) return;
    setState(() => _hit = hit);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final pointer = _pointer;
    final cell = pointer == null ? null : _cellAt(pointer);
    if (cell == null || !linkModifierDown) {
      _ask++;
      _set(null);
      return;
    }
    final hit = findLinkAt(
      widget.pane.terminal,
      cell,
      paths: paneHasLocalPaths(widget.pane),
    );
    if (hit == null || hit.kind == TerminalLinkKind.url) {
      _ask++;
      _set(hit);
      return;
    }
    // A path is a link only when it exists (A10 D7): ask, then show.
    final ask = ++_ask;
    final found = await ref
        .read(linkResolverProvider)
        .resolve(hit.target, cwd: widget.pane.cwd);
    if (!mounted || ask != _ask) return;
    _set(found == null ? null : hit);
  }

  void _click(Offset local) {
    if (!linkModifierDown) return;
    final cell = _cellAt(local);
    if (cell == null) return;
    final hit = findLinkAt(
      widget.pane.terminal,
      cell,
      paths: paneHasLocalPaths(widget.pane),
    );
    if (hit == null) return;
    unawaited(activateLink(ref, context, hit, widget.pane));
  }

  @override
  Widget build(BuildContext context) {
    final hit = _hit;
    return MouseRegion(
      onHover: (e) {
        _pointer = e.localPosition;
        unawaited(_refresh());
      },
      onExit: (_) {
        _pointer = null;
        unawaited(_refresh());
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _down =
            e.kind == PointerDeviceKind.mouse && e.buttons == kPrimaryButton
            ? e.localPosition
            : null,
        onPointerUp: (e) {
          final down = _down;
          _down = null;
          if (down != null && (e.localPosition - down).distance < kTouchSlop) {
            _click(e.localPosition);
          }
        },
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.builder(
              context,
              hit == null ? SystemMouseCursors.text : SystemMouseCursors.click,
            ),
            if (hit != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('link.underline'),
                    painter: _UnderlinePainter(
                      hit: hit,
                      viewKey: widget.viewKey,
                      terminal: widget.pane.terminal,
                      repaint: widget.scrollController,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  _UnderlinePainter({
    required this.hit,
    required this.viewKey,
    required this.terminal,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final LinkHit hit;
  final GlobalKey<TerminalViewState> viewKey;
  final Terminal terminal;

  @override
  void paint(Canvas canvas, Size size) {
    final render = viewKey.currentState?.renderTerminal;
    if (render == null) return;
    final paint = Paint()
      ..color = ShellxDesktopColors.accent
      ..strokeWidth = 1;
    final line = render.lineHeight;
    for (var y = hit.begin.y; y <= hit.end.y; y++) {
      final x0 = y == hit.begin.y ? hit.begin.x : 0;
      final x1 = y == hit.end.y ? hit.end.x : terminal.viewWidth;
      final a = render.getOffset(CellOffset(x0, y));
      final b = render.getOffset(CellOffset(x1, y));
      if (a.dy + line < 0 || a.dy > size.height) continue;
      canvas.drawLine(
        Offset(a.dx, a.dy + line - 1.5),
        Offset(b.dx, a.dy + line - 1.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_UnderlinePainter old) =>
      old.hit != hit || old.terminal != terminal;
}

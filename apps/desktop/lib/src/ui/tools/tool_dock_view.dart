import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../browser/browser_engine.dart';
import '../../tools/tool_dock.dart';
import '../../tools/tool_dock_state.dart';
import '../../tools/tool_entry.dart';
import '../../tools/tool_page.dart';
import '../../tools/tool_pages.dart';
import '../../tools/tool_registry.dart';
import '../terminal/device_pixel_lines.dart';
import '../theme/shellx_desktop_theme.dart';
import 'tool_actions.dart';
import 'tool_bar.dart';
import 'tool_dialogs.dart';

/// D5: a chip's height.
const double kToolChipsHeight = 30;

/// V2-3 D3: the dock of workspace [workspaceId] — the chips (from two
/// tools), the bar (D17) and the page. [focusNode] is the window's: while
/// it is the primary focus the page has the keyboard (D10). [covered]: a
/// menu, dialog or panel is open over the window (D7).
class ToolDockView extends ConsumerStatefulWidget {
  const ToolDockView({
    super.key,
    required this.workspaceId,
    required this.focusNode,
    required this.covered,
    required this.onChord,
    required this.onLeave,
  });

  final String workspaceId;
  final FocusNode focusNode;
  final bool covered;

  /// D10: a ShellX chord the page handed back.
  final void Function(String chord) onChord;

  /// The dock closed (or its last chip): the window moves the keyboard.
  final VoidCallback onLeave;

  @override
  ConsumerState<ToolDockView> createState() => _ToolDockViewState();
}

class _ToolDockViewState extends ConsumerState<ToolDockView> {
  ToolActions get _actions => ToolActions(ref);
  ToolDockController get _dock => ref.read(toolDockProvider.notifier);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(ToolDockView old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  ToolPage? get _page {
    final active = ref.read(toolDockProvider).of(widget.workspaceId).active;
    return active == null
        ? null
        : ref.read(toolPagesProvider.notifier).existing(active);
  }

  /// D10: the page has the keyboard exactly while the dock's own node is
  /// the primary focus; anywhere else (a bar button, a pane) it is
  /// Flutter's.
  void _onFocus() {
    final engine = _page?.engine;
    if (engine == null) return;
    unawaited(
      widget.focusNode.hasPrimaryFocus
          ? engine.focusContent()
          : engine.releaseFocus(),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // D3: Esc on the bar leaves "Expand".
    final dock = ref.read(toolDockProvider).of(widget.workspaceId);
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        dock.zoom) {
      _dock.setZoom(widget.workspaceId, false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _closeTool(String id) {
    _dock.closeTool(widget.workspaceId, id);
    if (!ref.read(toolDockProvider).of(widget.workspaceId).open) {
      widget.onLeave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ws = widget.workspaceId;
    final dock = ref.watch(toolDockProvider.select((d) => d.of(ws)));
    final tools = ref.watch(toolRegistryProvider);
    ref.watch(toolPagesProvider);
    final byId = {for (final t in tools) t.id: t};
    final chips = [for (final id in dock.tools) ?byId[id]];
    if (chips.isEmpty) return const SizedBox.shrink();
    final active =
        chips.where((t) => t.id == dock.active).firstOrNull ?? chips.first;
    final page = ref.read(toolPagesProvider.notifier).existing(active.id);
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: Semantics(
        container: true,
        label: l10n.toolDockLabel(active.name),
        child: ColoredBox(
          color: ShellxDesktopColors.bgTerminal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips.length >= 2)
                _ToolChips(
                  tools: chips,
                  active: active.id,
                  onSelect: (id) => _dock.activate(ws, id),
                  onClose: _closeTool,
                ),
              ListenableBuilder(
                listenable: page ?? const _Never(),
                builder: (context, _) => ToolBar(
                  tool: active,
                  state: page?.state,
                  zoomed: dock.zoom,
                  onBack: () => unawaited(page?.back()),
                  onReload: () => unawaited(page?.reload()),
                  onStop: () => unawaited(page?.stop()),
                  onBackToTool: () => unawaited(page?.backToTool()),
                  onPhone: () => _actions.togglePhone(active),
                  onZoom: () => _dock.setZoom(ws, !dock.zoom),
                  onBrowser: () => unawaited(
                    _actions.openInBrowser(
                      active,
                      url: page?.state.url ?? active.uri,
                    ),
                  ),
                  onEdit: () => unawaited(_actions.edit(context, active)),
                  onCopyUrl: () => unawaited(_actions.copyUrl(active)),
                  onCloseDock: () {
                    _dock.close(ws);
                    widget.onLeave();
                  },
                  onClose: () => _closeTool(active.id),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: _ToolPageHost(
                  key: ValueKey('tool.host.${active.id}'),
                  tool: active,
                  covered: widget.covered,
                  focusNode: widget.focusNode,
                  onChord: widget.onChord,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A listenable that never fires (the bar before its page exists).
final class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// D5: one chip per open tool; the one on show is selected (D18).
class _ToolChips extends StatelessWidget {
  const _ToolChips({
    required this.tools,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final List<ToolEntry> tools;
  final String active;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: kToolChipsHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s4),
        children: [
          for (final t in tools)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ShellxSpace.s2,
                vertical: ShellxSpace.s4,
              ),
              child: Semantics(
                button: true,
                selected: t.id == active,
                label: t.name,
                child: InkWell(
                  key: Key('tool.chip.${t.id}'),
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  onTap: () => onSelect(t.id),
                  child: Container(
                    padding: const EdgeInsets.only(left: ShellxSpace.s8),
                    decoration: BoxDecoration(
                      color: t.id == active
                          ? ShellxDesktopColors.rowSelected
                          : null,
                      borderRadius: BorderRadius.circular(ShellxRadius.r6),
                      border: Border.all(color: ShellxDesktopColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(
                            t.name,
                            style: ShellxText.small.copyWith(
                              color: ShellxDesktopColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          key: Key('tool.chip.${t.id}.close'),
                          tooltip: l10n.toolClose,
                          iconSize: 12,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onClose(t.id),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The page of [tool]: made when first shown (D14), shown while this
/// lives (retries run only then, D13), the D13 panels, the D9 download
/// line, and on Windows the stand-in while something covers it (D7).
class _ToolPageHost extends ConsumerStatefulWidget {
  const _ToolPageHost({
    super.key,
    required this.tool,
    required this.covered,
    required this.focusNode,
    required this.onChord,
  });

  final ToolEntry tool;
  final bool covered;
  final FocusNode focusNode;
  final void Function(String chord) onChord;

  @override
  ConsumerState<_ToolPageHost> createState() => _ToolPageHostState();
}

class _ToolPageHostState extends ConsumerState<_ToolPageHost> {
  ToolPage? _page;

  /// One view per page, built once: a new widget would be a second
  /// platform view for the same web view.
  Widget? _view;

  @override
  void initState() {
    super.initState();
    // Never while building: making a page changes the pages provider.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    if (!mounted) return;
    final page = ref.read(toolPagesProvider.notifier).open(widget.tool);
    page.onShortcut = widget.onChord;
    page.onContentClicked = widget.focusNode.requestFocus;
    page.onOpenOutside = (url) => unawaited(ToolActions(ref).openOutside(url));
    page.presenter = (dialog) =>
        showToolJsDialog(context, page.tool.name, dialog);
    page.setShown(true);
    setState(() {
      _page = page;
      _view = page.engine.buildView();
    });
    _syncVisible();
    if (widget.focusNode.hasPrimaryFocus) {
      unawaited(page.engine.focusContent());
    }
  }

  @override
  void didUpdateWidget(_ToolPageHost old) {
    super.didUpdateWidget(old);
    if (old.covered != widget.covered) _syncVisible();
  }

  /// D7: an engine that covers Flutter is hidden while anything is over
  /// it, or while a panel shows instead of the page.
  void _syncVisible() {
    final page = _page;
    if (page == null || !page.engine.coversFlutter) return;
    final s = page.state;
    final hide = widget.covered || s.error != null || s.download != null;
    unawaited(page.engine.setVisible(!hide));
  }

  @override
  void dispose() {
    // No ref here (the element is going): the page itself is enough. A page
    // that was unloaded meanwhile ignores all of this.
    final page = _page;
    if (page != null) {
      page.presenter = null;
      page.onShortcut = null;
      page.onContentClicked = null;
      page.onOpenOutside = null;
      page.setShown(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final view = _view;
    // The page went (unloaded for another, D5): this host makes it again.
    if (page != null &&
        ref.watch(
          toolPagesProvider.select((ids) => !ids.contains(page.tool.id)),
        )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _page = null;
          _view = null;
        });
        _attach();
      });
    }
    if (page == null || view == null) return const SizedBox.expand();
    return ListenableBuilder(
      listenable: page,
      builder: (context, _) {
        _syncVisible();
        final s = page.state;
        final l10n = AppLocalizations.of(context);
        final hideNative =
            page.engine.coversFlutter &&
            (widget.covered || s.error != null || s.download != null);
        return Stack(
          fit: StackFit.expand,
          children: [
            KeyedSubtree(
              key: ValueKey('tool.view.${page.tool.id}'),
              child: view,
            ),
            if (s.error case final kind?)
              _ErrorPanel(
                kind: kind,
                tool: page.tool,
                onReload: () => unawaited(page.reload()),
                onBrowser: () => unawaited(
                  ToolActions(ref).openInBrowser(page.tool, url: s.url),
                ),
              ),
            if (s.download case final url?)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _DownloadLine(
                  onBrowser: () => unawaited(
                    ToolActions(ref).openInBrowser(page.tool, url: url),
                  ),
                  onDismiss: page.dismissDownload,
                ),
              ),
            if (hideNative && widget.covered)
              Positioned.fill(
                child: ColoredBox(
                  key: const Key('tool.covered'),
                  color: ShellxDesktopColors.bgTerminal,
                  child: Center(
                    child: Text(
                      l10n.toolCovered(page.tool.name),
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// D13: what a failed load shows instead of the page.
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.kind,
    required this.tool,
    required this.onReload,
    required this.onBrowser,
  });

  final BrowserLoadErrorKind kind;
  final ToolEntry tool;
  final VoidCallback onReload;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = switch (kind) {
      BrowserLoadErrorKind.refused => l10n.toolRefused(tool.hostPort),
      BrowserLoadErrorKind.ats => l10n.toolAtsBlocked,
      BrowserLoadErrorKind.crashed => l10n.toolCrashed,
      BrowserLoadErrorKind.unavailable => l10n.toolNeedsWebView2,
      BrowserLoadErrorKind.dns => l10n.toolLoadFailed(l10n.toolReasonDns),
      BrowserLoadErrorKind.timeout => l10n.toolLoadFailed(
        l10n.toolReasonTimeout,
      ),
      BrowserLoadErrorKind.certificate => l10n.toolLoadFailed(
        l10n.toolReasonCertificate,
      ),
      BrowserLoadErrorKind.unreachable => l10n.toolLoadFailed(
        l10n.toolReasonUnreachable,
      ),
      BrowserLoadErrorKind.other => l10n.toolLoadFailed(l10n.toolReasonOther),
    };
    // D13: refused and crashed reload; ATS and a missing runtime can only
    // go to the browser; the others offer both.
    final reload =
        kind != BrowserLoadErrorKind.ats &&
        kind != BrowserLoadErrorKind.unavailable;
    final browser =
        kind != BrowserLoadErrorKind.refused &&
        kind != BrowserLoadErrorKind.crashed;
    return ColoredBox(
      key: Key('tool.error.${kind.name}'),
      color: ShellxDesktopColors.bgTerminal,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(ShellxSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: ShellxSpace.s12),
                Wrap(
                  spacing: ShellxSpace.s8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (reload)
                      FilledButton(
                        key: const Key('tool.error.reload'),
                        onPressed: onReload,
                        child: Text(l10n.toolReload),
                      ),
                    if (browser)
                      OutlinedButton(
                        key: const Key('tool.error.browser'),
                        onPressed: onBrowser,
                        child: Text(l10n.toolOpenInBrowser),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// D9: "This tool wants to download a file…" with the browser button.
class _DownloadLine extends StatelessWidget {
  const _DownloadLine({required this.onBrowser, required this.onDismiss});
  final VoidCallback onBrowser;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('tool.download'),
      color: ShellxDesktopColors.warnBg,
      padding: const EdgeInsets.symmetric(
        horizontal: ShellxSpace.s12,
        vertical: ShellxSpace.s6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.toolDownloadBlocked,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
            ),
          ),
          TextButton(
            key: const Key('tool.download.browser'),
            onPressed: onBrowser,
            child: Text(l10n.toolOpenInBrowser),
          ),
          IconButton(
            key: const Key('tool.download.close'),
            tooltip: l10n.actionClose,
            iconSize: 14,
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// D3: the strip that drags the dock's width; a slider for screen readers
/// and the keyboard (5 % a step).
class ToolDockHandle extends StatefulWidget {
  const ToolDockHandle({
    super.key,
    required this.contentWidth,
    required this.dockWidth,
    required this.fraction,
    required this.onFraction,
  });

  final double contentWidth;
  final double dockWidth;
  final double fraction;
  final ValueChanged<double> onFraction;

  @override
  State<ToolDockHandle> createState() => _ToolDockHandleState();
}

class _ToolDockHandleState extends State<ToolDockHandle> {
  bool _hovered = false;
  double? _from;
  double _moved = 0;

  void _width(double px) => widget.onFraction(
    toolDockFraction(width: widget.contentWidth, dockWidth: px),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dpr = View.of(context).devicePixelRatio;
    final active = _hovered || _from != null;
    String percent(double f) => '${(f * 100).round()} %';
    return Semantics(
      slider: true,
      label: l10n.toolHandleLabel,
      value: percent(widget.fraction),
      increasedValue: percent(widget.fraction + 0.05),
      decreasedValue: percent(widget.fraction - 0.05),
      onIncrease: () => _width(widget.dockWidth + widget.contentWidth * 0.05),
      onDecrease: () => _width(widget.dockWidth - widget.contentWidth * 0.05),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const Key('tool.handle'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) => setState(() {
            _from = widget.dockWidth;
            _moved = 0;
          }),
          onPanUpdate: (d) {
            final from = _from;
            if (from == null) return;
            _moved += d.delta.dx;
            _width(from - _moved);
          },
          onPanEnd: (_) => setState(() => _from = null),
          onPanCancel: () => setState(() => _from = null),
          child: DevicePixelLine(
            vertical: true,
            color: active
                ? ShellxDesktopColors.accent
                : ShellxDesktopColors.line,
            devicePixels: hairlineDevicePixels(dpr) * (active ? 3 : 1),
            devicePixelRatio: dpr,
          ),
        ),
      ),
    );
  }
}

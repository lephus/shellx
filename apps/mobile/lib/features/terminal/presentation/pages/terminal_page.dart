import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_page_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_tab_controller.dart';
import 'package:shellx_mobile/features/terminal/presentation/controllers/terminal_workspace.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_metrics.dart';
import 'package:shellx_mobile/features/terminal/presentation/terminal_shortcuts.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/extra_keys_bar.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/pinch_zoom.dart';
import 'package:shellx_mobile/features/terminal/presentation/widgets/session_picker.dart';
import 'package:shellx_mobile/shared/shared.dart';
import 'package:xterm/xterm.dart';

/// Spec §9.2 #4 and the design's "Terminal" section: dark chrome bar (machine name, status line,
/// "Aa"), tab row, xterm, extra keys attached to the keyboard; in landscape the name and tabs
/// share one row next to a keyboard button. Pops with a [TerminalExit] when it must close.
@RoutePage()
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.agentId, required this.machineName});

  final String agentId;
  final String machineName;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  /// Inside the terminal view, around the cells (design `.term`: `padding: 8px 10px 6px`).
  static const EdgeInsets _terminalPadding = EdgeInsets.fromLTRB(10, 8, 10, 6);

  late final TerminalPageController _controller = getIt<TerminalPageController>(param1: widget.agentId);
  late final void Function() _stopExit;
  final FocusNode _terminalFocus = FocusNode();
  TerminalGrid _grid = fallbackGrid;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _stopExit = _controller.exit.subscribe(_onExit);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _stopExit();
    _terminalFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Pops this page with [exit] after the current frame: the exit can already be known while the
  /// page is first built (a machine that is no longer pinned), and navigating during a build is
  /// not allowed. A sheet or dialog still open on top (the session picker, a confirmation, the
  /// font size) is closed first, or the router would pop it with [exit] as its result. A page that
  /// another navigation already took off the stack (a sign-out replaces it with the login page)
  /// pops nothing: the top route is not its.
  void _onExit(TerminalExit? exit) {
    if (exit == null || _leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      Navigator.of(context).popUntil((other) => other is! PopupRoute);
      if (route.isCurrent) context.router.maybePop(exit);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _prepare() async {
    if (!mounted || _controller.closing.peek()) return;
    final sessions = await _controller.prepare();
    if (sessions == null || !mounted || _controller.closing.peek()) return;
    if (sessions.isEmpty) {
      if (_controller.workspace.tabs.peek().isEmpty) await _controller.openNew(_grid);
      return;
    }
    final choice = await showSessionPicker(context, sessions);
    if (!mounted || _controller.closing.peek()) return;
    switch (choice) {
      case AttachSession(:final session):
        await _controller.attach(session, _grid);
      case OpenNewSession():
        await _controller.openNew(_grid);
      case null:
        break;
    }
  }

  Future<void> _close(TerminalTabController tab) async {
    if (tab.isLive.peek()) {
      final strings = S.of(context);
      final confirmed = await showConfirmDialog(
        context,
        message: strings.terminalCloseConfirm,
        confirmLabel: strings.terminalCloseTab,
      );
      if (!confirmed || !mounted) return;
    }
    await _controller.close(tab);
  }

  /// "Dán" and the hardware paste shortcut: `ShellxTerminal.paste` normalises the line breaks
  /// and adds the bracketed-paste markers when the program asked for them.
  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null && mounted) _controller.paste(text);
  }

  /// "Sao chép" and the hardware copy shortcut.
  Future<void> _copy(TerminalTabController tab) async {
    final range = tab.selection.selection;
    if (range == null) return;
    final copied = S.of(context).copied;
    final text = tab.terminal.peek().buffer.getText(range);
    tab.selection.clearSelection();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _controller.popupHandler.showSuccess(title: copied);
  }

  void _toggleKeyboard() {
    if (_terminalFocus.hasFocus) {
      _terminalFocus.unfocus();
    } else {
      _terminalFocus.requestFocus();
    }
  }

  Future<void> _showFontSize() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Watch((context) {
          final size = _controller.fontSize.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(S.of(context).fontSizeTooltip, style: context.typo.subHeader.bold)),
                  Text(size.toStringAsFixed(0), style: context.typo.subHeader),
                ],
              ),
              Row(
                children: [
                  Text('A', style: context.typo.metadata11.copyWith(color: context.colors.disable)),
                  Expanded(
                    child: Slider(
                      min: AppSettings.minFontSize,
                      max: AppSettings.maxFontSize,
                      divisions: (AppSettings.maxFontSize - AppSettings.minFontSize).round(),
                      value: size,
                      onChanged: _controller.setFontSize,
                    ),
                  ),
                  Text('A', style: context.typo.title.copyWith(color: context.colors.disable)),
                ],
              ),
            ],
          );
        }),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: TerminalColors.chrome,
        // Once the page is leaving, the workspace may already be disposed; nothing below
        // reads it again. Every Watch that does is inside [_body], replaced here in the next frame
        // (a parent rebuilds before its children), and the controller writes none of the signals
        // they read in the meantime.
        body: Watch((context) => _controller.closing.value ? const SizedBox.expand() : _body(context)),
      ),
    );
  }

  /// Only [Watch]es read signals below, so that [build]'s own Watch depends on
  /// [TerminalPageController.closing] alone.
  Widget _body(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final workspace = _controller.workspace;
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: landscape
              ? _ChromeBar(
                  onBack: () => context.router.maybePop(),
                  title: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      widget.machineName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.paragraph.bold.copyWith(color: TerminalColors.title),
                    ),
                  ),
                  middle: _TabStrip(
                    workspace: workspace,
                    closing: _controller.closing,
                    canOpen: _controller.canOpen,
                    onOpen: () => _controller.openNew(_grid),
                    onClose: _close,
                    inline: true,
                  ),
                  trailing: IconButton(
                    tooltip: S.of(context).keyboardTooltip,
                    icon: const Icon(Icons.keyboard_outlined, color: TerminalColors.cyan),
                    onPressed: _toggleKeyboard,
                  ),
                )
              : Column(
                  children: [
                    _ChromeBar(
                      onBack: () => context.router.maybePop(),
                      title: _TitleBlock(name: widget.machineName, controller: _controller),
                      trailing: IconButton(
                        tooltip: S.of(context).fontSizeTooltip,
                        onPressed: _showFontSize,
                        icon: Text(
                          'Aa',
                          style: context.typo.subHeader15.bold.copyWith(color: TerminalColors.cyan),
                        ),
                      ),
                    ),
                    _TabStrip(
                      workspace: workspace,
                      closing: _controller.closing,
                      canOpen: _controller.canOpen,
                      onOpen: () => _controller.openNew(_grid),
                      onClose: _close,
                    ),
                  ],
                ),
        ),
        ConnectionBanner(
          backend: _controller.backend,
          onReconnectReplaced: _controller.reconnectReplaced,
          showReconnecting: false,
        ),
        Watch(
          (context) => _controller.busy.value ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2),
        ),
        Expanded(
          child: ColoredBox(
            color: TerminalColors.background,
            // Landscape: keep the cells clear of the notch; top and bottom belong to the bars.
            child: SafeArea(
              top: false,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) => Watch((context) {
                  // Read first: set before the workspace is disposed (see [build]).
                  if (_controller.closing.value) return const SizedBox.expand();
                  final fontSize = _controller.fontSize.value;
                  // The size the terminal view gives its cells, so the session opens at the size
                  // the view then reports (never below 1×1, else the fallback).
                  final cells = Size(
                    (constraints.maxWidth - _terminalPadding.horizontal).clamp(0, double.infinity),
                    (constraints.maxHeight - _terminalPadding.vertical).clamp(0, double.infinity),
                  );
                  _grid =
                      measureTerminalGrid(cells, shellxTerminalStyle(fontSize), MediaQuery.textScalerOf(context)) ??
                      fallbackGrid;
                  final active = workspace.activeTab.value;
                  final notice = _controller.notice.value;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: active == null
                            ? _NoTab(busy: _controller.busy.value, onOpen: () => _controller.openNew(_grid))
                            : _TerminalPane(
                                key: ValueKey(active.id),
                                tab: active,
                                closing: _controller.closing,
                                focusNode: _terminalFocus,
                                fontSize: fontSize,
                                padding: _terminalPadding,
                                onFontSize: _controller.setFontSize,
                                onCopy: () => _copy(active),
                                onPaste: _paste,
                                onCloseTab: () => _controller.close(active),
                                onOpenNew: () => _controller.replaceWithNew(active, _grid),
                                onReattach: () => _controller.reattach(active),
                              ),
                      ),
                      if (notice != null)
                        Positioned(
                          top: 8,
                          left: 12,
                          right: 12,
                          child: _FloatingNotice(text: notice, onTap: _controller.dismissNotice),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
        Container(
          color: context.colors.keyboardBackground,
          child: SafeArea(
            top: false,
            child: ExtraKeysBar(controller: workspace.extraKeys, onKey: _controller.sendKey, onPaste: _paste),
          ),
        ),
      ],
    );
  }
}

/// The dark bar above the tabs (`.tbar`).
class _ChromeBar extends StatelessWidget {
  const _ChromeBar({required this.onBack, required this.title, required this.trailing, this.middle});

  final VoidCallback onBack;
  final Widget title;
  final Widget? middle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          IconButton(
            tooltip: S.of(context).backToMachines,
            icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: TerminalColors.cyan),
            onPressed: onBack,
          ),
          if (middle == null)
            Expanded(child: title)
          else ...[
            title,
            const SizedBox(width: 10),
            Expanded(child: middle!),
          ],
          trailing,
        ],
      ),
    );
  }
}

/// Machine name and the status line ("Đã kết nối · mã hóa đầu cuối").
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.name, required this.controller});

  final String name;
  final TerminalPageController controller;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      final relay = controller.relayState.value;
      final reconnecting = relay == RelayConnectionState.disconnected;
      // The channel only works while the relay does (the fakes keep the machine ready then).
      final ready = controller.machineState.value is MachineReady && relay == RelayConnectionState.connected;
      final status = reconnecting
          ? strings.bannerReconnecting
          : ready
          ? strings.terminalConnected
          : strings.terminalConnecting;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typo.subHeader15.bold.copyWith(color: TerminalColors.title),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  // Design: green when connected, amber while connecting or reconnecting.
                  color: ready ? context.colors.okDot : TerminalColors.yellow,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.metadata12.copyWith(color: TerminalColors.dim, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.workspace,
    required this.closing,
    required this.canOpen,
    required this.onOpen,
    required this.onClose,
    this.inline = false,
  });

  final TerminalWorkspace workspace;

  /// [TerminalPageController.closing]: read before [workspace], which may be disposed then.
  final ReadonlySignal<bool> closing;
  final ReadonlySignal<bool> canOpen;
  final VoidCallback onOpen;
  final ValueChanged<TerminalTabController> onClose;

  /// Landscape: part of the chrome bar instead of its own row.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      if (closing.value) return const SizedBox(height: 44);
      final tabs = workspace.tabs.value;
      final activeIndex = workspace.activeIndex.value;
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: inline
            ? null
            : const BoxDecoration(
                color: TerminalColors.chrome,
                border: Border(bottom: BorderSide(color: TerminalColors.line)),
              ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (index, tab) in tabs.indexed)
              _TabChip(
                key: ValueKey('tab-${tab.id}'),
                tab: tab,
                closing: closing,
                selected: index == activeIndex,
                onSelect: () => workspace.select(index),
                onClose: () => onClose(tab),
                closeTooltip: strings.terminalCloseTab,
              ),
            IconButton(
              tooltip: strings.terminalOpenNew,
              icon: const Icon(Icons.add, size: 20, color: TerminalColors.cyan),
              onPressed: canOpen.value ? onOpen : null,
            ),
          ],
        ),
      );
    });
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.tab,
    required this.closing,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.closeTooltip,
  });

  final TerminalTabController tab;

  /// Read before [tab], which is disposed with the workspace.
  final ReadonlySignal<bool> closing;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      if (closing.value) return const SizedBox.shrink();
      final live = tab.isLive.value;
      return Padding(
        padding: const EdgeInsets.only(top: 5, right: 2),
        child: Material(
          color: selected ? TerminalColors.background : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          child: InkWell(
            onTap: onSelect,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: live ? TerminalColors.green : TerminalColors.dim,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tab.title.value,
                    style: TextStyle(
                      fontFamily: FontFamily.jetBrainsMono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? const Color(0xFFEAF3F5) : TerminalColors.dim,
                    ),
                  ),
                  Tooltip(
                    message: closeTooltip,
                    child: InkWell(
                      onTap: onClose,
                      child: const SizedBox(
                        width: 36,
                        height: 39,
                        child: Icon(Icons.close, size: 14, color: TerminalColors.dim),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// No tab yet: the session list is loading, or every tab was closed.
class _NoTab extends StatelessWidget {
  const _NoTab({required this.busy, required this.onOpen});

  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final dim = context.typo.paragraph.copyWith(color: TerminalColors.dim);
    if (busy) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(strings.sessionsLoading, style: dim),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.terminalNoTabs, style: dim),
          12.sizedHeight,
          AppButton(
            title: strings.terminalOpenNew,
            height: 44,
            backgroundColor: TerminalColors.cyan,
            textColor: TerminalColors.onCyan,
            onTap: onOpen,
          ),
        ],
      ),
    );
  }
}

class _TerminalPane extends StatelessWidget {
  const _TerminalPane({
    super.key,
    required this.tab,
    required this.closing,
    required this.focusNode,
    required this.fontSize,
    required this.padding,
    required this.onFontSize,
    required this.onCopy,
    required this.onPaste,
    required this.onCloseTab,
    required this.onOpenNew,
    required this.onReattach,
  });

  final TerminalTabController tab;

  /// Read before [tab], which is disposed with the workspace.
  final ReadonlySignal<bool> closing;
  final FocusNode focusNode;
  final double fontSize;
  final EdgeInsets padding;
  final ValueChanged<double> onFontSize;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenNew;
  final VoidCallback onReattach;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    return Watch((context) {
      if (closing.value) return const SizedBox.expand();
      final banner = tab.banner.value;
      return Stack(
        children: [
          Positioned.fill(
            child: PinchToZoom(
              fontSize: fontSize,
              onFontSize: onFontSize,
              // `terminalShortcuts` maps the hardware copy/paste chords to ShellX intents that
              // xterm's own actions do not handle; they do what "Sao chép" and "Dán" do.
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ShellxPasteIntent: CallbackAction<ShellxPasteIntent>(
                    onInvoke: (_) {
                      onPaste();
                      return null;
                    },
                  ),
                  ShellxCopyIntent: CallbackAction<ShellxCopyIntent>(
                    onInvoke: (_) {
                      onCopy();
                      return null;
                    },
                  ),
                },
                // xterm adds the MediaQuery padding (status bar, home indicator) inside the view;
                // the bars around the terminal already keep clear of them.
                child: MediaQuery.removePadding(
                  context: context,
                  removeLeft: true,
                  removeTop: true,
                  removeRight: true,
                  removeBottom: true,
                  child: TerminalView(
                    tab.terminal.value,
                    controller: tab.selection,
                    focusNode: focusNode,
                    theme: TerminalColors.theme,
                    textStyle: shellxTerminalStyle(fontSize),
                    padding: padding,
                    autofocus: true,
                    deleteDetection: true,
                    readOnly: !tab.isLive.value,
                    shortcuts: terminalShortcuts(defaultTargetPlatform),
                  ),
                ),
              ),
            ),
          ),
          // Every child is positioned, so the stack fills the pane.
          Positioned(
            top: 8,
            right: 8,
            child: ListenableBuilder(
              listenable: tab.selection,
              builder: (context, _) => tab.selection.selection == null
                  ? const SizedBox.shrink()
                  : FilledButton.tonalIcon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(strings.copyAction),
                    ),
            ),
          ),
          if (banner != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: _EndedCard(banner: banner, onCloseTab: onCloseTab, onOpenNew: onOpenNew, onReattach: onReattach),
            ),
        ],
      );
    });
  }
}

/// Design "Phiên đã kết thúc": the tab keeps its content; the card offers the next step.
class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.banner, required this.onCloseTab, required this.onOpenNew, required this.onReattach});

  final TabBanner banner;
  final VoidCallback onCloseTab;
  final VoidCallback onOpenNew;
  final VoidCallback onReattach;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final (title, body) = switch (banner.notice) {
      TabNotice.exited => (strings.sessionEnded, strings.sessionExitedBody(banner.exitCode ?? 0)),
      TabNotice.sessionEnded => (strings.sessionEnded, strings.sessionGoneBody),
      TabNotice.takenOver => (strings.tabTakenOver, null),
      TabNotice.closedByHost => (strings.tabClosedByHost, null),
      TabNotice.failed => (ErrorText(strings).appError(banner.errorCode!, banner.detail ?? ''), null),
    };
    final takenOver = banner.notice == TabNotice.takenOver;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TerminalColors.chrome2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TerminalColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.typo.subHeader15.bold.copyWith(color: Colors.white)),
          if (body != null) ...[
            4.sizedHeight,
            Text(body, style: context.typo.paragraph13.copyWith(color: TerminalColors.dim)),
          ],
          10.sizedHeight,
          Row(
            children: [
              Expanded(
                child: AppButton(
                  title: strings.closeTab,
                  height: 44,
                  radius: 11,
                  backgroundColor: TerminalColors.secondaryAction,
                  textColor: const Color(0xFFE6F0F2),
                  onTap: onCloseTab,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  title: takenOver ? strings.tabReattach : strings.terminalOpenNew,
                  height: 44,
                  radius: 11,
                  backgroundColor: TerminalColors.cyan,
                  textColor: TerminalColors.onCyan,
                  onTap: takenOver ? onReattach : onOpenNew,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Design "session_limit": a floating notice over the terminal.
class _FloatingNotice extends StatelessWidget {
  const _FloatingNotice({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: TerminalColors.noticeBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TerminalColors.noticeBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: TerminalColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: context.typo.paragraph13.bold.copyWith(color: TerminalColors.noticeText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

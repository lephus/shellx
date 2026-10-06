import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
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
import 'package:shellx_mobile/features/voice/presentation/controllers/voice_composer_controller.dart';
import 'package:shellx_mobile/features/voice/presentation/widgets/mic_button.dart';
import 'package:shellx_mobile/features/voice/presentation/widgets/voice_composer.dart';
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

  /// Voice spec §3.1: the composer of this page; a line goes to whichever tab is active.
  late final VoiceComposerController _voice;
  late final AppLifecycleListener _lifecycle;
  late final void Function() _stopVoicePhase;
  final FocusNode _terminalFocus = FocusNode();
  TerminalGrid _grid = fallbackGrid;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _stopExit = _controller.exit.subscribe(_onExit);
    // Creating it is cheap: the recognizer is only initialised on the first mic tap.
    _voice = getIt<VoiceComposerController>()..attach(canSend: _activeTabLive, onSubmit: _controller.submitLine);
    // A call, the lock screen or the app switcher stops the listen; the text stays (spec §5).
    _lifecycle = AppLifecycleListener(onInactive: _voice.pause, onHide: _voice.pause);
    // Spec §3.1: while the composer is open the keyboard types into it, not into the terminal.
    var wasOpen = false;
    _stopVoicePhase = _voice.phase.subscribe((phase) {
      final open = phase != VoicePhase.closed;
      if (open && !wasOpen) _terminalFocus.unfocus();
      if (!open && wasOpen && mounted) _terminalFocus.requestFocus();
      wasOpen = open;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _stopExit();
    // Leaving the page cancels the listen and drops the text (spec §5).
    _stopVoicePhase();
    _lifecycle.dispose();
    _voice.dispose();
    _terminalFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _activeTabLive() =>
      !_controller.closing.peek() && (_controller.workspace.activeTab.peek()?.isLive.peek() ?? false);

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
    final listing = await _controller.prepare();
    if (listing == null || !mounted || _controller.closing.peek()) return;
    if (listing.isEmpty) {
      if (_controller.workspace.tabs.peek().isEmpty) await _controller.openNew(_grid);
      return;
    }
    await _pick(listing);
  }

  /// `+` (terminal sharing §9.1): the picker when a desktop terminal or a ShellX session is not open
  /// as a tab yet, else a new session at once.
  Future<void> _onAdd() async {
    final listing = await _controller.pickable();
    if (listing == null || !mounted || _controller.closing.peek()) return;
    if (listing.isEmpty) {
      await _controller.openNew(_grid);
      return;
    }
    await _pick(listing);
  }

  Future<void> _pick(SessionListing listing) async {
    final choice = await showSessionPicker(context, listing);
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

  /// A live ShellX session asks first (closing it stops its programs). A desktop terminal never asks:
  /// `×` only detaches, and a toast says the terminal keeps running (terminal sharing §9.2).
  Future<void> _close(TerminalTabController tab) async {
    final strings = S.of(context);
    if (tab.isLive.peek() && !tab.isDesktop) {
      final confirmed = await showConfirmDialog(
        context,
        message: strings.terminalCloseConfirm,
        confirmLabel: strings.terminalCloseTab,
      );
      if (!confirmed || !mounted) return;
    }
    final stillRunning = tab.leavesTerminalRunning;
    await _controller.close(tab);
    if (stillRunning && mounted) _controller.popupHandler.showInfo(title: strings.desktopStillRunning);
  }

  /// "Dán" and the hardware paste shortcut: `ShellxTerminal.paste` sanitises the text, turns
  /// line breaks into CR and adds the bracketed-paste markers when the program asked for them. A
  /// clipboard the platform cannot read shows the ErrorText toast.
  Future<void> _paste() async {
    final String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (error) {
      _clipboardFailed(error);
      return;
    }
    if (text != null && mounted) _controller.paste(text);
  }

  /// "Sao chép" and the hardware copy shortcut.
  Future<void> _copy(TerminalTabController tab) async {
    final range = tab.selection.selection;
    if (range == null) return;
    final copied = S.of(context).copied;
    final text = tab.terminal.peek().buffer.getText(range);
    tab.selection.clearSelection();
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error) {
      _clipboardFailed(error);
      return;
    }
    if (mounted) _controller.popupHandler.showSuccess(title: copied);
  }

  /// Only the error's type is logged, never the clipboard's content.
  void _clipboardFailed(Object error) {
    if (kDebugMode) debugPrint('Clipboard error: ${error.runtimeType}');
    if (mounted) _controller.popupHandler.showError(title: ErrorText(S.of(context)).describe(error));
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
                    onOpen: _onAdd,
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
                      onOpen: _onAdd,
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
                            ? _NoTab(busy: _controller.busy.value, onOpen: _onAdd)
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
                                onCloseTab: () => _close(active),
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
        Watch((context) {
          if (_voice.phase.value == VoicePhase.closed) return const SizedBox.shrink();
          final tab = workspace.activeTab.value;
          return VoiceComposer(
            controller: _voice,
            target: tab == null ? null : '${tab.title.value} · ${widget.machineName}',
            canSend: tab?.isLive.value ?? false,
            onOpenSettings: () => unawaited(getIt<ExternalLinks>().openAppSettingsOrToast()),
          );
        }),
        Container(
          color: context.colors.keyboardBackground,
          child: SafeArea(
            top: false,
            child: ExtraKeysBar(
              controller: workspace.extraKeys,
              onKey: _controller.sendKey,
              onPaste: _paste,
              leading: Watch(
                (context) => (workspace.activeTab.value?.isLive.value ?? false)
                    ? MicButton(
                        controller: _voice,
                        onTap: () => _voice.toggleMic(Localizations.localeOf(context).languageCode),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
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
      final machine = controller.machineState.value;
      // The channel only works while the relay does (the fakes keep the machine ready then).
      final ready = machine is MachineReady && relay == RelayConnectionState.connected;
      // Design: green when connected, amber while connecting or reconnecting, red when it failed
      // and the user has to act (another instance took the connection, the machine is offline, …).
      final (String status, Color dot) = switch ((relay, machine)) {
        (RelayConnectionState.replaced, _) => (strings.bannerReplaced, TerminalColors.red),
        (RelayConnectionState.disconnected, _) => (strings.bannerReconnecting, TerminalColors.yellow),
        (_, MachineFailed(:final failure)) => (ErrorText(strings).machine(failure), TerminalColors.red),
        _ when ready => (strings.terminalConnected, context.colors.okDot),
        _ => (strings.terminalConnecting, TerminalColors.yellow),
      };
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
                key: const ValueKey('terminal-status-dot'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
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
                // A desktop terminal keeps running: `×` closes the tab, not the session.
                closeTooltip: tab.isDesktop ? strings.closeTab : strings.terminalCloseTab,
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

  static const double _maxLabelWidth = 180;

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
                  if (tab.isDesktop) ...[
                    Icon(
                      Icons.desktop_windows_outlined,
                      size: 13,
                      color: selected ? const Color(0xFFEAF3F5) : TerminalColors.dim,
                      semanticLabel: S.of(context).desktopTerminalLabel,
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Window titles of desktop terminals run long ("user@host: ~/path — zsh — 80×24").
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
                    child: Text(
                      // A tab whose session never started has no shell name or index to show.
                      tab.hasSession ? tab.title.value : S.of(context).terminalFailedTabTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FontFamily.jetBrainsMono,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? const Color(0xFFEAF3F5) : TerminalColors.dim,
                      ),
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
      final computerDrives = tab.showDriverBanner.value;
      return Stack(
        children: [
          Positioned.fill(
            // Terminal sharing §9.2: a tap on the terminal takes the size back from the computer;
            // scrolling, long-press selection and pinch do not.
            child: _TapListener(
              onTap: tab.claimSize,
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
          ),
          // Over the cells, never above them: pushing the terminal down would change its size and
          // send a resize that takes the size back on its own.
          if (computerDrives)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _DriverBanner(onTap: tab.claimSize),
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
              child: _EndedCard(
                banner: banner,
                isDesktop: tab.isDesktop,
                canReattach: tab.canReattach,
                onCloseTab: onCloseTab,
                onOpenNew: onOpenNew,
                onReattach: onReattach,
              ),
            ),
        ],
      );
    });
  }
}

/// Design "Phiên đã kết thúc": the tab keeps its content; the card offers the next step. A
/// `spawn_failed` shows its reason in the same card (spec §12). A desktop terminal that is gone
/// offers only "Đóng tab" (terminal sharing §9.2: it cannot be reattached, and a new session would
/// not be that window); one the computer disconnected offers "Gắn lại".
class _EndedCard extends StatelessWidget {
  const _EndedCard({
    required this.banner,
    required this.isDesktop,
    required this.canReattach,
    required this.onCloseTab,
    required this.onOpenNew,
    required this.onReattach,
  });

  final TabBanner banner;
  final bool isDesktop;
  final bool canReattach;
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
      TabNotice.closedByHost => (isDesktop ? strings.desktopClosedByHost : strings.tabClosedByHost, null),
      TabNotice.failed => (ErrorText(strings).appError(banner.errorCode!, banner.detail ?? ''), null),
      TabNotice.desktopClosed => (strings.desktopWindowClosed, null),
      TabNotice.terminalGone => (strings.desktopTerminalGone, null),
    };
    // The second button: "Gắn lại", "Mở phiên mới" on a ShellX tab, none on a desktop terminal that is gone.
    final String? secondLabel = canReattach ? strings.tabReattach : (isDesktop ? null : strings.terminalOpenNew);
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
              if (secondLabel != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    title: secondLabel,
                    height: 44,
                    radius: 11,
                    backgroundColor: TerminalColors.cyan,
                    textColor: TerminalColors.onCyan,
                    onTap: canReattach ? onReattach : onOpenNew,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Calls [onTap] for a real tap only: one pointer, released within [kLongPressTimeout], having moved
/// less than [kTouchSlop]. Built on a [Listener], so it never joins the gesture arena and the
/// terminal's own gestures (scroll, selection, pinch) work as before.
class _TapListener extends StatefulWidget {
  const _TapListener({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TapListener> createState() => _TapListenerState();
}

class _TapListenerState extends State<_TapListener> {
  /// Pointers currently down.
  final Set<int> _down = {};

  /// The candidate tap: its pointer, where and when it went down. Cleared as soon as the gesture
  /// stops being a tap (a second pointer, too much movement).
  ({int pointer, Offset position})? _candidate;

  /// Held down this long it is a long press (selection), not a tap. A timer rather than the events'
  /// time stamps, which synthesized events may leave at zero.
  Timer? _longPress;

  void _onDown(PointerDownEvent event) {
    _down.add(event.pointer);
    _longPress?.cancel();
    if (_down.length == 1) {
      _candidate = (pointer: event.pointer, position: event.position);
      _longPress = Timer(kLongPressTimeout, () => _candidate = null);
    } else {
      _candidate = null;
    }
  }

  @override
  void dispose() {
    _longPress?.cancel();
    super.dispose();
  }

  void _onMove(PointerMoveEvent event) {
    final candidate = _candidate;
    if (candidate == null || candidate.pointer != event.pointer) return;
    if ((event.position - candidate.position).distance >= kTouchSlop) _candidate = null;
  }

  void _onUp(PointerUpEvent event) {
    _down.remove(event.pointer);
    final candidate = _candidate;
    if (candidate == null || candidate.pointer != event.pointer) return;
    _candidate = null;
    _longPress?.cancel();
    if ((event.position - candidate.position).distance < kTouchSlop) widget.onTap();
  }

  void _onCancel(PointerCancelEvent event) {
    _down.remove(event.pointer);
    if (_candidate?.pointer == event.pointer) _candidate = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}

/// Design "Terminal trên máy tính": the computer has taken this desktop terminal's size (someone typed
/// or resized the window there). Tapping it, the terminal, or typing hands the size back.
class _DriverBanner extends StatelessWidget {
  const _DriverBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('desktop-driver-banner'),
      color: TerminalColors.driverBannerBackground,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: TerminalColors.driverBannerBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.desktop_windows_outlined, size: 18, color: TerminalColors.yellow),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.of(context).desktopDriverBanner,
                  style: context.typo.paragraph13.bold.copyWith(color: TerminalColors.yellow),
                ),
              ),
            ],
          ),
        ),
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

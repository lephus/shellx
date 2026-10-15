import 'dart:async';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/features/app/connection_banner.dart';
import 'package:shellx_mobile/features/tools/domain/tool_texts.dart';
import 'package:shellx_mobile/features/tools/presentation/controllers/tool_page_controller.dart';
import 'package:shellx_mobile/features/tools/presentation/tool_web_engine.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// V2-4 E15: one tool of the computer, over the machine's page: a bar (‹, the name, "localhost:5173 ·
/// qua máy tính", ↻, ⋯), a thin progress line, and the page in a web view. The states of E16 cover
/// the web view; a lost channel keeps the page under a strip. Android back goes back in the page
/// first.
@RoutePage()
class ToolPage extends StatefulWidget {
  const ToolPage({super.key, required this.agentId, required this.tool});

  final String agentId;
  final ToolInfo tool;

  @override
  State<ToolPage> createState() => _ToolPageState();
}

class _ToolPageState extends State<ToolPage> {
  late final ToolPageController _controller = getIt<ToolPageController>(param1: widget.agentId, param2: widget.tool);
  late final ToolWebEngine _engine = getIt<ToolWebEngine>();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<(ToolNotice, int?)>? _notices;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // E13: served while the app is on screen; `hidden` and `paused` close the servers.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _controller.setForeground(
        state == AppLifecycleState.resumed || state == AppLifecycleState.inactive,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _notices = _controller.notices.listen(_notice);
    _engine
      ..askExternal = _askExternal
      ..attach(
        ToolWebCallbacks(
          decide: _controller.decide,
          onProgress: _controller.progressed,
          onPageStarted: _controller.pageStarted,
          onPageFinished: _controller.pageFinished,
          onLoadError: _controller.loadFailed,
          onCrashed: _controller.crashed,
          onFileChooser: _controller.fileChooser,
          alert: _alert,
          confirm: _confirm,
          prompt: _prompt,
        ),
      );
    _controller.start(_engine, AppToolTexts(S.of(context)));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_notices?.cancel());
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _notice((ToolNotice, int?) notice) {
    if (!mounted) return;
    final s = S.of(context);
    final (kind, port) = notice;
    _controller.popupHandler.showInfo(
      title: switch (kind) {
        ToolNotice.noDownloads => s.toolNoDownloads,
        ToolNotice.siblingOff => s.toolSiblingOff(port ?? 0),
      },
    );
  }

  /// E12: another site opens in the phone's browser, once the user says so.
  Future<void> _askExternal(Uri url) async {
    if (!mounted) return;
    final s = S.of(context);
    final open = await showConfirmDialog(context, message: s.toolOpenExternal(url.host), confirmLabel: s.linkSheetOpen);
    if (open) await getIt<ExternalLinks>().openOrToast(url);
  }

  /// E12: the page's dialogs are the app's, titled with the tool's name (a page cannot pass for
  /// ShellX).
  Future<void> _alert(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tool.dialog'),
        title: Text(S.of(context).toolDialogTitle(widget.tool.name)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tool.dialog'),
        title: Text(S.of(context).toolDialogTitle(widget.tool.name)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<String?> _prompt(String message, String? value) async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _PromptDialog(title: S.of(context).toolDialogTitle(widget.tool.name), message: message, value: value),
    );
  }

  /// Android back: a page back in the web view first, else the tool page closes.
  Future<void> _back() async {
    if (await _controller.back()) return;
    _leave();
  }

  /// Past the [PopScope] (it only stops `maybePop`): the page closes.
  void _leave() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Column(
            children: [
              _bar(context),
              if (_controller.backend case final backend?)
                ConnectionBanner(
                  backend: backend,
                  onReconnectReplaced: () => unawaited(getIt<SessionHolder>().reconnectReplaced()),
                ),
              Watch(_strips),
              Watch(_progress),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _engine.view()),
                    Positioned.fill(child: Watch(_cover)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          IconButton(
            key: const Key('tool.back'),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new, color: colors.primary),
            onPressed: _leave,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tool.name,
                  key: const Key('tool.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.subHeader.bold.copyWith(color: colors.primaryText),
                ),
                2.sizedHeight,
                Text(
                  s.toolViaComputer(widget.tool.port),
                  key: const Key('tool.subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('tool.reload'),
            tooltip: s.toolReload,
            icon: Icon(Icons.refresh, color: colors.primary),
            onPressed: () => unawaited(_controller.reload()),
          ),
          PopupMenuButton<String>(
            key: const Key('tool.menu'),
            icon: Icon(Icons.more_horiz, color: colors.primary),
            onSelected: (choice) {
              if (choice == 'home') _controller.home();
              if (choice == 'reload') unawaited(_controller.reload());
            },
            itemBuilder: (context) => [
              PopupMenuItem(key: const Key('tool.home'), value: 'home', child: Text(s.toolHome)),
              PopupMenuItem(key: const Key('tool.menuReload'), value: 'reload', child: Text(s.toolReload)),
            ],
          ),
        ],
      ),
    );
  }

  /// E16 "Đang kết nối lại…" over a page kept as it is; E3 the other port.
  Widget _strips(BuildContext context) {
    final s = S.of(context);
    final alias = _controller.alias.value;
    final reconnecting = _controller.phase.value == ToolPhase.reconnecting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reconnecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: NoticeBanner(key: const Key('tool.reconnecting'), text: s.toolReconnecting),
          ),
        if (alias != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: NoticeBanner(
              key: const Key('tool.otherPort'),
              text: s.toolOtherPort(alias, widget.tool.port),
              tone: NoticeTone.info,
            ),
          ),
      ],
    );
  }

  /// The thin progress line; past 3 s "Đang tải qua máy tính… (n request)" (E20).
  Widget _progress(BuildContext context) {
    final colors = context.colors;
    final loading = _controller.loading.value;
    final slow = _controller.slowRequests.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 2,
          child: loading
              ? LinearProgressIndicator(
                  key: const Key('tool.progress'),
                  value: _controller.progress.value / 100,
                  minHeight: 2,
                  color: colors.link,
                  backgroundColor: colors.divider,
                )
              : null,
        ),
        if (slow != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text(
              S.of(context).toolSlow(slow),
              key: const Key('tool.slow'),
              style: context.typo.paragraph13.copyWith(color: colors.secondaryText),
            ),
          ),
      ],
    );
  }

  /// E16: what covers the web view while the page cannot be shown.
  Widget _cover(BuildContext context) {
    final s = S.of(context);
    final colors = context.colors;
    final phase = _controller.phase.value;
    final (key, text, waiting) = switch (phase) {
      ToolPhase.opening || ToolPhase.busy => ('tool.loading', s.toolLoadingTunnel, true),
      ToolPhase.ready when _controller.firstLoad.value => ('tool.loading', s.toolLoadingTunnel, true),
      ToolPhase.refused => ('tool.refused', s.toolRefusedPhone(widget.tool.port), true),
      ToolPhase.disabled => ('tool.disabled', s.toolDisabled, false),
      ToolPhase.gone => ('tool.gone', s.toolGone, false),
      ToolPhase.unavailable => ('tool.unavailable', s.toolNeedsDesktop, false),
      ToolPhase.ready || ToolPhase.reconnecting || ToolPhase.paused || ToolPhase.closed => (null, null, false),
    };
    if (key == null || text == null) return const SizedBox.shrink();
    return ColoredBox(
      key: Key(key),
      color: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waiting) ...[const AppCircularProgress(size: 24), 16.sizedHeight],
              Text(
                text,
                textAlign: TextAlign.center,
                style: context.typo.subHeader15.copyWith(color: colors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's `prompt`: the app's dialog, titled with the tool's name; its field lives as long as it.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, required this.message, required this.value});

  final String title;
  final String message;
  final String? value;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _field = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('tool.dialog'),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message),
        TextField(key: const Key('tool.dialogField'), controller: _field, autofocus: true),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _field.text),
        child: Text(MaterialLocalizations.of(context).okButtonLabel),
      ),
    ],
  );
}

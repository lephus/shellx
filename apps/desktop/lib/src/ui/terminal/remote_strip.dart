import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/remote_state.dart';
import '../../remote/ssh_reconnector.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'remote_marks.dart';

/// UI-A8 §3.2: the bottom strip of a lost SSH pane. Drawn over the
/// terminal (no layout change, no resize). Three kinds of "not retrying
/// right now" read differently: waiting (countdown), needs a sign-in
/// (lockout protection), and gave up (30 minutes).
class RemoteStrip extends ConsumerStatefulWidget {
  const RemoteStrip({super.key, required this.pane});
  final PaneSession pane;

  @override
  ConsumerState<RemoteStrip> createState() => _RemoteStripState();
}

class _RemoteStripState extends ConsumerState<RemoteStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The countdown ticks only while a retry is waiting; managed here, not
    // while building.
    ref.listenManual(
      sshReconnectorProvider.select((all) => all[widget.pane.id]),
      (_, retry) => _keepTicking(_counting(retry)),
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(RemoteStrip old) {
    super.didUpdateWidget(old);
    _keepTicking(_counting(ref.read(sshReconnectorProvider)[widget.pane.id]));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _counting(RetryInfo? retry) =>
      widget.pane.remoteState == RemoteState.disconnected &&
      retry != null &&
      !retry.retrying &&
      !retry.stopped &&
      retry.nextAt != null;

  void _keepTicking(bool counting) {
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  String? _detail(
    AppLocalizations l10n,
    RetryInfo? retry,
    bool lost,
    bool hookHint,
  ) {
    if (!lost) return hookHint ? l10n.sshFailedHookHint : null;
    if (retry == null) return null;
    if (retry.retrying) return l10n.sshRetrying;
    if (retry.needsSignIn) return l10n.sshNeedsSignIn;
    if (retry.stopped) return l10n.sshAutoRetryStopped;
    final nextAt = retry.nextAt;
    if (nextAt == null) return null;
    final left = nextAt.difference(ref.read(reconnectClockProvider)());
    return l10n.sshRetryIn((left.inMilliseconds / 1000).ceil().clamp(0, 60));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = widget.pane;
    final host = cleanServerText(pane.remote?.hostKey ?? '');
    final state = pane.remoteState;
    final retry = ref.watch(sshReconnectorProvider)[pane.id];
    final lost = state == RemoteState.disconnected;
    final hookHint =
        state == RemoteState.failed &&
        pane.exitCode != 255 &&
        (pane.remote?.launch.usesHook ?? false);
    final main = lost
        ? l10n.sshStateDisconnected(host)
        : l10n.sshStateFailed(host);
    final detail = _detail(l10n, retry, lost, hookHint);
    final reconnector = ref.read(sshReconnectorProvider.notifier);
    final buttons = <Widget>[
      if (retry == null || !retry.retrying)
        _StripButton(
          label: lost ? l10n.sshReconnectAction : l10n.sshRetryAction,
          primary: true,
          onPressed: () => unawaited(reconnector.reconnectNow(pane.id)),
        ),
      if (hookHint)
        _StripButton(
          label: l10n.sshRetryPlainAction,
          onPressed: () =>
              unawaited(reconnector.reconnectNow(pane.id, withoutHook: true)),
        ),
      _StripButton(
        label: l10n.sshClosePaneAction,
        onPressed: () =>
            ref.read(terminalTabsProvider.notifier).closePane(pane.id),
      ),
    ];
    final windows = Theme.of(context).platform == TargetPlatform.windows;
    // A1 §4: the primary button is on the right on macOS.
    final ordered = windows ? buttons : buttons.reversed.toList();
    final mainText = Text(
      main,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
    );
    return Semantics(
      key: Key('remote.strip.${pane.id}'),
      container: true,
      liveRegion: true,
      label: detail == null ? main : '$main · $detail',
      child: Container(
        height: ShellxSizes.remoteStripFor(MediaQuery.textScalerOf(context)),
        padding: const EdgeInsets.symmetric(
          horizontal: ShellxSizes.remoteStripPadH,
        ),
        decoration: const BoxDecoration(
          color: ShellxDesktopColors.bgSidebar,
          border: Border(top: BorderSide(color: ShellxDesktopColors.line)),
        ),
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.link_off,
                size: ShellxSizes.icon,
                color: ShellxDesktopColors.err,
              ),
            ),
            const SizedBox(width: ShellxSpace.s6),
            Flexible(
              child: ExcludeSemantics(
                child: pane.remote?.isTmux == false && lost
                    ? Tooltip(message: l10n.sshTmuxHint, child: mainText)
                    : mainText,
              ),
            ),
            if (detail != null)
              Flexible(
                child: LayoutBuilder(
                  builder: (context, c) => c.maxWidth < 40
                      ? const SizedBox.shrink()
                      : ExcludeSemantics(
                          child: Text(
                            ' · $detail',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ShellxText.body.copyWith(
                              color: ShellxDesktopColors.textSecondary,
                            ),
                          ),
                        ),
                ),
              ),
            const Spacer(),
            for (final b in ordered) ...[
              const SizedBox(width: ShellxSpace.s6),
              b,
            ],
          ],
        ),
      ),
    );
  }
}

class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ShellxSizes.remoteStripButton,
    child: TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s8),
        minimumSize: const Size(64, ShellxSizes.remoteStripButton),
        backgroundColor: primary
            ? ShellxDesktopColors.primary
            : ShellxDesktopColors.rowSelected,
        foregroundColor: primary
            ? ShellxDesktopColors.onPrimary
            : ShellxDesktopColors.textPrimary,
        textStyle: ShellxText.small.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

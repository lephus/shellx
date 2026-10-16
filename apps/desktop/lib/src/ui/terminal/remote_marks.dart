import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../remote/remote_state.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// C0, DEL, C1, the line and paragraph separators, and the Unicode bidi
/// controls (marks, embeddings, overrides, isolates, Arabic letter mark):
/// a server name must not reorder the text around it.
final _controls = RegExp(
  r'[\x00-\x1f\x7f-\x9f\u2028\u2029\u200e\u200f\u061c\u202a-\u202e\u2066-\u2069]',
);

/// Text the server (or a config file) supplied, safe to show: control
/// characters (escape sequences, newlines) removed.
String cleanServerText(String text) => text.replaceAll(_controls, '');

String? _host(PaneSession pane) {
  final key = pane.remote?.hostKey;
  return key == null ? null : cleanServerText(key);
}

/// UI-A8 §2.1: the pane's SSH or tmux mark; nothing for a local shell.
class RemoteMark extends StatelessWidget {
  const RemoteMark(this.pane, {super.key});
  final PaneSession pane;

  @override
  Widget build(BuildContext context) {
    final remote = pane.remote;
    if (remote == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final host = _host(pane);
    final session = remote.tmuxSession;
    final tmux = session == null ? null : cleanServerText(session);
    final message = tmux == null
        ? l10n.sidebarRemoteMark(host ?? '')
        : host == null
        ? l10n.sidebarTmuxMark(tmux)
        : l10n.sidebarTmuxRemoteMark(tmux, host);
    return Tooltip(
      message: message,
      excludeFromSemantics: true,
      child: Icon(
        tmux == null ? Icons.dns_outlined : Icons.view_quilt_outlined,
        key: Key('mark.remote.${pane.id}'),
        size: ShellxSizes.remoteMark,
        color: ShellxDesktopColors.textSecondary,
      ),
    );
  }
}

/// UI-A8 §2.2: "connecting" — a 4 px dot centred in the dot box, a shape
/// none of A1's three dots has (WCAG 1.4.1). No pulse, so nothing to turn
/// off for reduced motion.
class ConnectingDot extends StatelessWidget {
  const ConnectingDot({
    super.key = const Key('dot.connecting'),
    this.box = ShellxSizes.dot,
  });
  final double box;

  @override
  Widget build(BuildContext context) {
    // 4 px in whatever box it replaces (UI-A8 §2.2).
    const size = ShellxSizes.connectingDot;
    return SizedBox(
      width: box,
      height: box,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// UI-A8 §8: ", on devbox" and the connection state for row and pane labels.
String remoteSemantics(AppLocalizations l10n, PaneSession pane) {
  final host = _host(pane);
  if (host == null) return '';
  final state = switch (pane.remoteState) {
    RemoteState.connecting => ', ${l10n.sshStateConnecting(host)}',
    RemoteState.disconnected => ', ${l10n.sshStateDisconnected(host)}',
    RemoteState.failed => ', ${l10n.sshStateFailed(host)}',
    _ => '',
  };
  return '${l10n.paneRemoteSuffix(host)}$state';
}

/// UI-A8 §8: what to announce when a pane's connection state changes; null
/// when nothing changed. A pane that was connecting after having been
/// connected once is a reconnect.
String? remoteAnnouncement(
  AppLocalizations l10n,
  PaneSession? before,
  PaneSession after,
) {
  final host = _host(after);
  if (before == null || host == null) return null;
  final was = before.remoteState;
  final now = after.remoteState;
  if (was == now) return null;
  return switch (now) {
    RemoteState.connected =>
      was == RemoteState.connecting && !before.everConnected
          ? l10n.sshAnnounceConnected(host)
          : l10n.sshAnnounceReconnected(host),
    // Only a live connection is news when it drops; a retry that fails on
    // its way (connecting to disconnected) is the same outage.
    RemoteState.disconnected =>
      was == RemoteState.connected ? l10n.sshAnnounceDisconnected(host) : null,
    _ => null,
  };
}

/// The page's listener: the focused pane of the selected tab, before and
/// after a change. Silent when the selection moved to another tab, the
/// focus moved to another pane, or the pane is not one reconnect made of
/// the earlier one ([resolve] follows replaced ids).
String? remoteAnnouncementBetween(
  AppLocalizations l10n,
  TerminalTabsState? before,
  TerminalTabsState after,
  int Function(int id) resolve,
) {
  if (before == null || before.selectedId != after.selectedId) return null;
  final was = before.selected?.focused;
  final now = after.selected?.focused;
  if (was == null || now == null || resolve(was.id) != now.id) return null;
  return remoteAnnouncement(l10n, was, now);
}

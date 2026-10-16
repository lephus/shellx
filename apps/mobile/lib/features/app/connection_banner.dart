import 'dart:async';

import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_mobile/core/core.dart';
import 'package:shellx_mobile/shared/shared.dart';

/// Spec §12: "Mất kết nối, đang thử lại…" while the relay reconnects, and a
/// manual "Kết nối lại" after close code 4001 (no automatic reconnect).
class ConnectionBanner extends StatefulWidget {
  const ConnectionBanner({
    super.key,
    required this.backend,
    required this.onReconnectReplaced,
    this.showReconnecting = true,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 8),
  });

  final ShellxBackend backend;
  final VoidCallback onReconnectReplaced;

  /// False on the terminal page, whose status line already says "Mất kết nối, đang thử lại…".
  final bool showReconnecting;
  final EdgeInsets padding;

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  StreamSubscription<RelayConnectionState>? _subscription;
  late RelayConnectionState _state;

  /// The first `connecting` after launch is not a lost connection.
  bool _hadConnectionOrFailure = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ConnectionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      // Cancelling takes effect at once; its future only reports cleanup (never awaited here).
      unawaited(_subscription?.cancel());
      _hadConnectionOrFailure = false;
      _subscribe();
    }
  }

  void _subscribe() {
    _observe(widget.backend.relayState);
    _subscription = widget.backend.relayStates.listen((state) => setState(() => _observe(state)));
  }

  void _observe(RelayConnectionState state) {
    _state = state;
    if (state == RelayConnectionState.connected || state == RelayConnectionState.disconnected) {
      _hadConnectionOrFailure = true;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final reconnecting =
        _state == RelayConnectionState.disconnected ||
        (_state == RelayConnectionState.connecting && _hadConnectionOrFailure);
    final replaced = _state == RelayConnectionState.replaced;
    if (!(reconnecting && widget.showReconnecting) && !replaced) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: NoticeBanner(
        text: reconnecting ? strings.bannerReconnecting : strings.bannerReplaced,
        leading: reconnecting ? const NoticeSpinner() : const Icon(Icons.link_off),
        action: replaced
            ? TextButton(onPressed: widget.onReconnectReplaced, child: Text(strings.bannerReconnectButton))
            : null,
      ),
    );
  }
}

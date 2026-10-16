import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Pending output that triggers an immediate flush (spec §6.5).
const int kFlushThresholdBytes = 16 * 1024;

/// Pending tool data that triggers an immediate flush (V2-4 E7): a full
/// `tool.data` or `tool.ws.msg` goes out at once, in a frame of its own.
const int kToolFlushThresholdBytes = kToolMaxChunkBytes;

/// One established encrypted channel to a phone.
///
/// Outgoing messages are batched: everything pending is sent
/// [flushInterval] after the first pending message, or immediately (in a
/// microtask, so a synchronous burst from one pump is collected first) once
/// pending `output` data reaches [kFlushThresholdBytes], or pending tool data
/// (`tool.data`, `tool.ws.msg`) [kToolFlushThresholdBytes]. A flush produces
/// as many TRANSPORT payloads as [splitIntoBatches] needs. Sealing is
/// serialized so Noise nonces go out in order.
///
/// If a batch fails to seal, or the relay reports it could not be sent, the
/// channel marks itself failed: it stops sending exactly like [close] (timer
/// cancelled, pending output dropped, later [enqueue]/[flush] are no-ops) and
/// calls [onFailure] exactly once. [close] itself never calls [onFailure].
final class AgentChannel {
  AgentChannel({
    required this.mobileId,
    required this.channelId,
    required this.name,
    required this.remoteStatic,
    required SecureChannel secure,
    required bool Function(RelayFrame frame) send,
    this.pairingSecret,
    this.onFailure,
    Duration flushInterval = const Duration(milliseconds: 16),
  }) : _secure = secure,
       _send = send,
       _flushInterval = flushInterval;

  final String mobileId;
  final ChannelId channelId;

  /// Device name from the HS1 payload.
  final String name;

  /// The phone's static public key proven by the handshake.
  final Uint8List remoteStatic;

  /// Pairing code used as PSK; non-null only for a pairing (IKpsk2) channel.
  final Uint8List? pairingSecret;

  /// Called exactly once when a batch fails to seal or the relay reports it
  /// could not be sent. Never called by [close].
  final void Function()? onFailure;

  final SecureChannel _secure;
  final bool Function(RelayFrame frame) _send;
  final Duration _flushInterval;
  final _pending = <AppMessage>[];
  int _pendingOutputBytes = 0;
  int _pendingToolBytes = 0;
  Timer? _timer;
  bool _flushScheduled = false;
  Future<void> _sendChain = Future.value();
  bool _closed = false;

  bool get isPairing => pairingSecret != null;

  Future<List<AppMessage>> open(Uint8List noiseMessage) =>
      _secure.open(noiseMessage);

  void enqueue(AppMessage message) {
    if (_closed) return;
    _pending.add(message);
    switch (message) {
      case OutputMessage(:final data):
        _pendingOutputBytes += data.length;
      case ToolData(:final data) || ToolWsMessage(:final data):
        _pendingToolBytes += data.length;
      default:
        break;
    }
    if (_pendingOutputBytes >= kFlushThresholdBytes ||
        _pendingToolBytes >= kToolFlushThresholdBytes) {
      _timer?.cancel();
      _timer = null;
      if (!_flushScheduled) {
        _flushScheduled = true;
        scheduleMicrotask(flush);
      }
    } else {
      _timer ??= Timer(_flushInterval, flush);
    }
  }

  void flush() {
    _flushScheduled = false;
    _timer?.cancel();
    _timer = null;
    if (_closed || _pending.isEmpty) return;
    final batches = splitIntoBatches(_pending);
    _pending.clear();
    _pendingOutputBytes = 0;
    _pendingToolBytes = 0;
    for (final batch in batches) {
      _sendChain = _sendChain
          .then((_) async {
            if (_closed) return;
            final payload = await _secure.seal(batch);
            if (_closed) return;
            final ok = _send(
              DataFrame(peer: mobileId, channel: channelId, payload: payload),
            );
            if (!ok) _fail();
          })
          .catchError((Object _) {
            _fail();
          });
    }
  }

  /// A batch could not be sealed, or the relay rejected it. Stops the
  /// channel exactly like [close] and notifies [onFailure] once.
  void _fail() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    onFailure?.call();
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}

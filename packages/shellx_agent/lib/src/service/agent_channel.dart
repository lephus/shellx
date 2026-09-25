import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Pending output that triggers an immediate flush (spec §6.5).
const int kFlushThresholdBytes = 16 * 1024;

/// Upper bound for a CBOR array header of up to 65535 items.
const int _arrayHeaderAllowance = 3;

/// Splits [messages], in order, into batches whose encoded CBOR array stays
/// within [kMaxSealedBatchBytes] (so each sealed DATA frame is ≤ 64 KiB).
/// Sizes are measured with [encodeBatch]; three full 16 KiB outputs fit in
/// one batch, four do not.
List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages) {
  final batches = <List<AppMessage>>[];
  var current = <AppMessage>[];
  var size = _arrayHeaderAllowance;
  for (final message in messages) {
    final messageSize = encodeBatch([message]).length - 1;
    if (current.isNotEmpty && size + messageSize > kMaxSealedBatchBytes) {
      batches.add(current);
      current = <AppMessage>[];
      size = _arrayHeaderAllowance;
    }
    current.add(message);
    size += messageSize;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// One established encrypted channel to a phone.
///
/// Outgoing messages are batched: everything pending is sent
/// [flushInterval] after the first pending message, or immediately (in a
/// microtask, so a synchronous burst from one pump is collected first) once
/// pending `output` data reaches [kFlushThresholdBytes]. A flush produces as
/// many TRANSPORT payloads as [splitIntoBatches] needs. Sealing is serialized
/// so Noise nonces go out in order.
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
    if (message is OutputMessage) _pendingOutputBytes += message.data.length;
    if (_pendingOutputBytes >= kFlushThresholdBytes) {
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

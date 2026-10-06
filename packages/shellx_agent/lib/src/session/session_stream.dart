import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'ring_buffer.dart';

/// The phone-facing half of a session (spec v1 §6.5): buffered output
/// addressed by `seq`, the attached phone, replay on attach and the send
/// window. Shared by shell sessions (`SessionManager`) and desktop
/// terminals (`DesktopSessionManager`); it does not know where bytes come
/// from and never decides when a session ends.
///
/// [append], [ack] and [restartWith] only change state; the owner calls
/// [pump] (so it can check, right after, whether a closing session has
/// drained). [attach] pumps itself, before the owner resizes and answers
/// `session.attached`.
final class SessionStream {
  SessionStream({
    required this.id,
    required int capacity,
    required int sendWindow,
    required void Function(String mobileId, AppMessage message) send,
  }) : _buffer = RingBuffer(capacity),
       _sendWindow = sendWindow,
       _send = send;

  final int id;
  final RingBuffer _buffer;
  final int _sendWindow;
  final void Function(String mobileId, AppMessage message) _send;

  /// The phone output goes to; null when nobody is attached.
  String? attachedMobileId;

  /// Next stream position to send to the attached phone.
  int _sent = 0;

  /// Highest position acknowledged by the attached phone.
  int _acked = 0;

  int get start => _buffer.start;
  int get end => _buffer.end;

  /// Every byte the buffer still holds, oldest first (the window's backlog,
  /// A1 §3.1).
  Uint8List get buffered =>
      _buffer.read(_buffer.start, _buffer.end - _buffer.start);

  /// Every buffered byte has been handed to the attached phone.
  bool get drained => _sent >= _buffer.end;

  void append(Uint8List data) => _buffer.append(data);

  /// Replaces the buffer with [data], positions continuing (spec §7.8). An
  /// attached phone gets `session.reset` and, on the next [pump], [data]
  /// from its first byte.
  void restartWith(Uint8List data) {
    _buffer.restartWith(data);
    final mobileId = attachedMobileId;
    if (mobileId == null) return;
    _send(mobileId, SessionReset(id: id));
    _sent = _buffer.start;
    _acked = _buffer.start;
  }

  /// Attaches [mobileId] from [lastSeq] and replays: `taken_over` to the
  /// previous phone, `session.reset` when [lastSeq] is outside the buffer.
  /// Returns the phone that was attached before. Does not send
  /// `session.attached`.
  String? attach(String mobileId, int lastSeq) {
    final previous = attachedMobileId;
    if (previous != null && previous != mobileId) {
      _send(previous, SessionDetached(id: id, reason: DetachReason.takenOver));
    }
    attachedMobileId = mobileId;
    if (lastSeq < _buffer.start || lastSeq > _buffer.end) {
      _send(mobileId, SessionReset(id: id));
      _sent = _buffer.start;
    } else {
      _sent = lastSeq;
    }
    _acked = _sent;
    pump();
    return previous;
  }

  void ack(int seq) => _acked = max(_acked, min(seq, _sent));

  /// Sends buffered output to the attached phone while the send window
  /// allows. Data overwritten before it could be sent triggers a reset.
  void pump() {
    final mobileId = attachedMobileId;
    if (mobileId == null) return;
    while (_sent < _buffer.end && _sent - _acked < _sendWindow) {
      if (_sent < _buffer.start) {
        _send(mobileId, SessionReset(id: id));
        _sent = _buffer.start;
        _acked = _buffer.start;
        continue;
      }
      final room = _sendWindow - (_sent - _acked);
      final count = min(min(kMaxOutputChunk, _buffer.end - _sent), room);
      final data = _buffer.read(_sent, count);
      final seq = _sent;
      // Advance before sending: the owner's outbound stream is synchronous,
      // so a listener may call back (e.g. to ack) before `_send` returns.
      _sent += count;
      _send(mobileId, OutputMessage(id: id, seq: seq, data: data));
    }
  }
}

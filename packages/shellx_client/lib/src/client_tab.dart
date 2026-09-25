import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

sealed class TabEvent {
  const TabEvent();
}

/// Terminal output, already decoded from UTF-8 as a stream: a character
/// split across two `output` messages is emitted whole.
final class TabOutput extends TabEvent {
  const TabOutput(this.text);
  final String text;
}

/// The agent restarted the stream from the start of its buffer: clear the
/// screen before writing further output.
final class TabReset extends TabEvent {
  const TabReset();
}

final class TabExited extends TabEvent {
  const TabExited(this.exitCode);
  final int exitCode;
}

final class TabDetached extends TabEvent {
  const TabDetached(this.reason);
  final DetachReason reason;
}

/// The session is gone or could not be used (e.g. `session_not_found`
/// after the agent restarted): the UI shows "Session ended".
final class TabError extends TabEvent {
  const TabError(this.code, this.message);
  final AppErrorCode code;
  final String message;
}

/// Send an ack after this many unacknowledged bytes (spec §6.5).
const int kAckThresholdBytes = 32 * 1024;

/// Or this long after the last output while bytes are unacknowledged.
const Duration kAckDelay = Duration(milliseconds: 100);

/// Keystrokes held for a tab that is not attached on the current channel:
/// at most this many, the oldest dropped first.
const int _maxHeldInputBytes = 64 * 1024;

/// One terminal tab attached to a session on a machine.
///
/// Events emitted before the first listener subscribes are buffered and
/// replayed to it (replayed output arrives before `attach()` returns);
/// after that the stream behaves as a plain broadcast stream.
final class ClientTab {
  @internal
  ClientTab({
    required this.id,
    required this.index,
    required this.shell,
    required int cols,
    required int rows,
    required void Function(AckMessage ack) sendAck,
  }) : _cols = cols,
       _rows = rows,
       _sendAck = sendAck {
    _decoder = _newDecoder();
  }

  final int id;
  final int index;
  final String shell;
  final void Function(AckMessage ack) _sendAck;

  late final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast(onListen: _replayBacklog);
  final _backlog = <TabEvent>[];
  bool _everListened = false;
  late ByteConversionSink _decoder;
  int _cols;
  int _rows;
  int _received = 0;
  int _acked = 0;
  bool _attached = true;
  Timer? _ackTimer;
  final _heldInput = BytesBuilder();

  /// Total output bytes received: the `last_seq` for re-attaching.
  int get received => _received;

  /// False after [TabDetached], [TabExited] or [TabError].
  bool get isAttached => _attached;

  Stream<TabEvent> get events => _events.stream;

  @internal
  int get cols => _cols;

  @internal
  int get rows => _rows;

  @internal
  void updateSize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
  }

  /// Called when (re-)attaching: the agent treats everything up to
  /// [received] as acknowledged.
  @internal
  void beginAttach() {
    _attached = true;
    _acked = _received;
  }

  /// Keystrokes are waiting for the agent to confirm the (re-)attach.
  @internal
  bool get hasHeldInput => _heldInput.isNotEmpty;

  /// Holds [data] (copied) after the keystrokes already held, keeping only
  /// the newest 64 KiB. Dropped when the tab ends.
  @internal
  void holdInput(Uint8List data) {
    _heldInput.add(data);
    final overflow = _heldInput.length - _maxHeldInputBytes;
    if (overflow > 0) {
      _heldInput.add(Uint8List.sublistView(_heldInput.takeBytes(), overflow));
    }
  }

  /// The held keystrokes, oldest first; none are held afterwards.
  @internal
  Uint8List takeHeldInput() => _heldInput.takeBytes();

  @internal
  void dropHeldInput() => _heldInput.clear();

  @internal
  void handleOutput(int seq, Uint8List data) {
    if (!_attached) return;
    final end = seq + data.length;
    if (end <= _received) return; // Duplicate.
    final fresh = seq < _received
        ? Uint8List.sublistView(data, _received - seq)
        : data;
    _received = end;
    _decoder.add(fresh);
    if (_received - _acked >= kAckThresholdBytes) {
      _flushAck();
    } else {
      _ackTimer?.cancel();
      _ackTimer = Timer(kAckDelay, _flushAck);
    }
  }

  @internal
  void handleReset() {
    // A fresh decoder drops any half-received multi-byte character.
    _decoder = _newDecoder();
    _received = 0;
    _acked = 0;
    _cancelAck();
    _emit(const TabReset());
  }

  @internal
  void handleExited(int exitCode) {
    _end();
    _emit(TabExited(exitCode));
  }

  @internal
  void handleDetached(DetachReason reason) {
    _end();
    _emit(TabDetached(reason));
  }

  @internal
  void handleError(AppErrorCode code, String message) {
    _end();
    _emit(TabError(code, message));
  }

  @internal
  void dispose() {
    _end();
    _events.close();
  }

  void _end() {
    _attached = false;
    _cancelAck();
    dropHeldInput();
  }

  void _flushAck() {
    _cancelAck();
    if (!_attached || _received <= _acked) return;
    _acked = _received;
    _sendAck(AckMessage(id: id, seq: _received));
  }

  void _cancelAck() {
    _ackTimer?.cancel();
    _ackTimer = null;
  }

  ByteConversionSink _newDecoder() =>
      const Utf8Decoder(allowMalformed: true).startChunkedConversion(
        _TextSink((text) {
          if (text.isNotEmpty) _emit(TabOutput(text));
        }),
      );

  void _emit(TabEvent event) {
    if (_events.isClosed) return;
    if (_everListened) {
      _events.add(event);
    } else {
      _backlog.add(event);
    }
  }

  void _replayBacklog() {
    if (_everListened) return;
    _everListened = true;
    for (final event in _backlog) {
      _events.add(event);
    }
    _backlog.clear();
  }
}

final class _TextSink implements Sink<String> {
  _TextSink(this._onText);
  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}

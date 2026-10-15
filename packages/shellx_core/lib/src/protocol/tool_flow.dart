import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'messages.dart';
import 'tool_rules.dart';

/// V2-4 E7: the unacknowledged bytes one stream may have in flight, per
/// direction.
const int kToolStreamWindow = 256 * 1024;

/// V2-4 E7: the unacknowledged bytes all the streams of one phone may have in
/// flight, per direction (the relay then never holds much for it, and its
/// heartbeat is still answered).
const int kToolPhoneWindow = 512 * 1024;

/// V2-4 E8, §5: one `tool.ack` (for every stream) at most this often.
const Duration kToolAckInterval = Duration(milliseconds: 50);

/// V2-4 E7: the bytes in flight to one peer over all its streams, in one
/// direction. A stream sends only while its own window and this one have
/// room; a stream blocked here is woken when another stream's bytes are
/// acknowledged.
final class ToolCredit {
  ToolCredit({this.limit = kToolPhoneWindow});

  final int limit;
  int _inFlight = 0;
  final _waiting = <void Function()>{};

  int get inFlight => _inFlight;

  bool _hasRoom(int bytes) => _inFlight + bytes <= limit;

  void _release(int bytes) {
    if (bytes <= 0) return;
    _inFlight -= bytes;
    if (_waiting.isEmpty) return;
    final waiting = [..._waiting];
    _waiting.clear();
    for (final wake in waiting) {
      wake();
    }
  }
}

/// V2-4 E7: one stream's bytes in flight in one direction, against its own
/// window and its peer's [credit]. Acknowledgements are cumulative.
final class ToolSendWindow {
  ToolSendWindow(this.credit, {this.limit = kToolStreamWindow});

  final ToolCredit credit;
  final int limit;
  int _sent = 0;
  int _acked = 0;
  bool _closed = false;

  int get sent => _sent;
  int get acked => _acked;
  int get inFlight => _sent - _acked;

  /// Room for [bytes] more in this window and in the peer's.
  bool canSend(int bytes) =>
      !_closed && inFlight + bytes <= limit && credit._hasRoom(bytes);

  void onSent(int bytes) {
    _sent += bytes;
    credit._inFlight += bytes;
  }

  /// [total] bytes were taken. False when that is more than was sent: the
  /// peer breaks the protocol (the caller ends the stream).
  bool onAck(int total) {
    if (total > _sent) return false;
    if (total <= _acked || _closed) return true;
    final freed = total - _acked;
    _acked = total;
    credit._release(freed);
    return true;
  }

  /// The stream is over: what it had in flight no longer counts.
  void close() {
    if (_closed) return;
    _closed = true;
    final freed = inFlight;
    _acked = _sent;
    credit._release(freed);
  }

  void _waitForCredit(void Function() wake) => credit._waiting.add(wake);
  void _stopWaiting(void Function() wake) => credit._waiting.remove(wake);
}

/// What lets a stream send one frame of data (V2-4 E7).
abstract interface class ToolPacer {
  /// [send] runs once a frame is granted: at once when the tokens are there
  /// and nobody waits, else in turn. It returns the bytes it sent, which are
  /// charged then, or null when it sent nothing (nothing is charged). The
  /// returned function withdraws a request not granted yet.
  void Function() acquire(int? Function() send);
}

/// No pacing: the phone's tool outbox limits its own frames (V2-4 E8).
final class ToolUnpaced implements ToolPacer {
  const ToolUnpaced();

  @override
  void Function() acquire(int? Function() send) {
    send();
    return () {};
  }
}

/// V2-4 E7: all the tool data of a computer stays under [bytesPerSecond]
/// and [framesPerSecond] (token buckets of [byteBurst] and [frameBurst]),
/// so terminals, AI and heartbeats keep room under the relay's 500 frames
/// per second. Requests are granted in order. The byte bucket may go into
/// debt by one frame (a grant charges what was sent).
final class ToolTokenPacer implements ToolPacer {
  ToolTokenPacer({
    this.bytesPerSecond = 8 * 1024 * 1024,
    this.byteBurst = 1024 * 1024,
    this.framesPerSecond = 150,
    this.frameBurst = 16,
    int Function()? clock,
  }) : _clock = clock ?? _stopwatch() {
    _frames = frameBurst * _unit;
    _bytes = byteBurst * _unit;
    _last = _clock();
  }

  final int bytesPerSecond;
  final int byteBurst;
  final int framesPerSecond;
  final int frameBurst;

  /// Microseconds from any fixed start (monotonic).
  final int Function() _clock;

  /// Tokens are kept ×1e6, so a microsecond adds the per-second rate.
  static const _unit = 1000000;
  late int _frames;
  late int _bytes;
  late int _last;
  final _queue = Queue<_Grant>();
  Timer? _timer;

  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  void _refill() {
    final now = _clock();
    final elapsed = now - _last;
    _last = now;
    if (elapsed <= 0) return;
    _frames = min(frameBurst * _unit, _frames + elapsed * framesPerSecond);
    _bytes = min(byteBurst * _unit, _bytes + elapsed * bytesPerSecond);
  }

  bool get _grantable => _frames >= _unit && _bytes > 0;

  void _charge(int? bytes) {
    if (bytes == null) return;
    _frames -= _unit;
    _bytes -= bytes * _unit;
  }

  @override
  void Function() acquire(int? Function() send) {
    _refill();
    if (_queue.isEmpty && _grantable) {
      _charge(send());
      return () {};
    }
    final grant = _Grant(send);
    _queue.add(grant);
    _schedule();
    return () => _queue.remove(grant);
  }

  void _schedule() {
    if (_timer != null || _queue.isEmpty) return;
    final frames = max(0, _unit - _frames);
    final bytes = max(0, 1 - _bytes);
    final wait = max(
      (frames + framesPerSecond - 1) ~/ framesPerSecond,
      (bytes + bytesPerSecond - 1) ~/ bytesPerSecond,
    );
    _timer = Timer(Duration(microseconds: wait), _fire);
  }

  void _fire() {
    _timer = null;
    _refill();
    while (_queue.isNotEmpty && _grantable) {
      _charge(_queue.removeFirst().send());
    }
    _schedule();
  }
}

final class _Grant {
  _Grant(this.send);
  final int? Function() send;
}

/// V2-4 E8, §5: what this side took of each stream, acknowledged together in
/// one `tool.ack` [interval] after the first unacknowledged byte (so at most
/// one per [interval]: each ack is a relay frame).
final class ToolAckBook {
  ToolAckBook(this._send, {this.interval = kToolAckInterval});

  final void Function(ToolAck ack) _send;
  final Duration interval;
  final _pending = <int, int>{};
  Timer? _timer;

  /// Every byte of stream [id] up to [total] was taken.
  void consumed(int id, int total) {
    final before = _pending[id];
    if (before != null && before >= total) return;
    _pending[id] = total;
    _timer ??= Timer(interval, _flush);
  }

  /// Stream [id] is over: nothing more is acknowledged for it.
  void forget(int id) => _pending.remove(id);

  /// The channel is gone: nothing pending is sent.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty) return;
    final acks = [
      for (final MapEntry(:key, :value) in _pending.entries) ...[key, value],
    ];
    _pending.clear();
    _send(ToolAck(acks));
  }
}

/// Pieces of the bytes [take] removes from the front of a queue of chunks.
final class _ByteQueue {
  final _chunks = Queue<Uint8List>();
  int length = 0;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    length += chunk.length;
  }

  Uint8List take(int count) {
    final out = Uint8List(count);
    var at = 0;
    while (at < count) {
      final head = _chunks.first;
      final n = min(head.length, count - at);
      out.setRange(at, at + n, head);
      at += n;
      if (n == head.length) {
        _chunks.removeFirst();
      } else {
        _chunks
          ..removeFirst()
          ..addFirst(Uint8List.sublistView(head, n));
      }
    }
    length -= count;
    return out;
  }
}

/// V2-4 E7: a byte stream (a response body on the desktop, a request body on
/// the phone) sent as `tool.data` pieces of at most [kToolMaxChunkBytes],
/// within [window] and as [pacer] allows. When it cannot send, it stops
/// reading [source] (never drops a byte); acknowledgements ([onAck]) let it
/// go on. The last piece carries `end`.
final class ToolBytesOut {
  ToolBytesOut({
    required this.id,
    required Stream<List<int>> source,
    required this.window,
    required this.pacer,
    required void Function(ToolMessage message) send,
    this.maxBytes,
    this.onTooLarge,
    this.onError,
    this.onDone,
  }) : _source = source,
       _send = send;

  final int id;
  final ToolSendWindow window;
  final ToolPacer pacer;
  final void Function(ToolMessage message) _send;
  final Stream<List<int>> _source;

  /// Past this many bytes the source is dropped and [onTooLarge] called.
  final int? maxBytes;
  final void Function()? onTooLarge;

  /// The source failed: nothing more is sent (the caller ends the stream).
  final void Function(Object error)? onError;

  /// The last piece went out.
  final void Function()? onDone;

  final _buffer = _ByteQueue();
  StreamSubscription<List<int>>? _subscription;
  bool _paused = false;

  /// A frame was asked of [pacer] and not granted yet.
  bool _asked = false;
  void Function()? _withdraw;
  int _total = 0;
  bool _ended = false;
  bool _finished = false;
  bool _cancelled = false;

  bool get finished => _finished;

  void start() {
    _subscription = _source.listen(
      _onData,
      onError: (Object error) {
        _stop();
        onError?.call(error);
      },
      onDone: () {
        _ended = true;
        _pump();
      },
      cancelOnError: true,
    );
  }

  void _onData(List<int> chunk) {
    if (_cancelled) return;
    _total += chunk.length;
    final limit = maxBytes;
    if (limit != null && _total > limit) {
      _stop();
      onTooLarge?.call();
      return;
    }
    _buffer.add(chunk);
    if (_buffer.length >= kToolMaxChunkBytes && !_paused) {
      _paused = true; // a full piece waits: read no more (never drop)
      _subscription?.pause();
    }
    _pump();
  }

  /// The peer took [total] bytes. False when that is more than was sent.
  bool onAck(int total) {
    if (!window.onAck(total)) return false;
    _pump();
    return true;
  }

  void _pump() {
    if (_cancelled || _finished || _asked) return;
    if (_buffer.length == 0) {
      if (_ended) _finish(Uint8List(0));
      return;
    }
    final size = min(_buffer.length, kToolMaxChunkBytes);
    if (!window.canSend(size)) {
      // Our own window opens with our acks; the shared one with anyone's.
      window._waitForCredit(_pump);
      return;
    }
    _asked = true;
    final withdraw = pacer.acquire(_sendOne);
    if (_asked) _withdraw = withdraw; // not granted at once
  }

  int? _sendOne() {
    _asked = false;
    _withdraw = null;
    if (_cancelled || _finished || _buffer.length == 0) return null;
    final size = min(_buffer.length, kToolMaxChunkBytes);
    if (!window.canSend(size)) {
      scheduleMicrotask(_pump);
      return null;
    }
    final data = _buffer.take(size);
    final last = _ended && _buffer.length == 0;
    window.onSent(size);
    _send(ToolData(id: id, data: data, end: last));
    if (last) {
      _finished = true;
      onDone?.call();
    } else {
      if (_paused && _buffer.length < kToolMaxChunkBytes) {
        _paused = false;
        _subscription?.resume();
      }
      scheduleMicrotask(_pump);
    }
    return size;
  }

  void _finish(Uint8List data) {
    _finished = true;
    _send(ToolData(id: id, data: data, end: true));
    onDone?.call();
  }

  void _stop() {
    _cancelled = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    unawaited(_subscription?.cancel());
  }

  /// Stops reading and sending; the window no longer counts it.
  void cancel() {
    _stop();
    window.close();
  }
}

/// V2-4 E7: the bytes of a stream as they arrive (`tool.data`), handed on in
/// order through [stream] to a sink that takes them at its own pace (an HTTP
/// request or response: `sink.addStream(inlet.stream)`). What the sink took
/// is reported to [onConsumed] (cumulative), which acknowledges it.
final class ToolBytesIn {
  ToolBytesIn({
    required void Function(int total) onConsumed,
    this.window = kToolStreamWindow,
    this.maxBytes,
  }) : _onConsumed = onConsumed;

  final void Function(int total) _onConsumed;
  final int window;

  /// More than this in all: [add] says no (413 on the phone, `too_large`
  /// from the desktop).
  final int? maxBytes;
  final _controller = StreamController<List<int>>();
  int _received = 0;
  int _consumed = 0;
  bool _ended = false;

  int get received => _received;
  bool get ended => _ended;

  /// Listen once.
  late final Stream<List<int>> stream = _controller.stream.map((chunk) {
    _consumed += chunk.length;
    _onConsumed(_consumed);
    return chunk;
  });

  /// A piece arrived. False when it breaks the rules (after the end, more in
  /// flight than [window], past [maxBytes]): the caller ends the stream.
  bool add(Uint8List data, {required bool end}) {
    if (_ended) return false;
    _received += data.length;
    if (_received - _consumed > window) return false;
    final limit = maxBytes;
    if (limit != null && _received > limit) return false;
    if (data.isNotEmpty) _controller.add(data);
    if (end) {
      _ended = true;
      unawaited(_controller.close());
    }
    return true;
  }

  /// Cuts the sink: [error] ends [stream] (an HTTP response the webview gets
  /// is then incomplete, never a clean end).
  void fail(Object error) {
    if (_controller.isClosed) return;
    _ended = true;
    _controller.addError(error);
    unawaited(_controller.close());
  }
}

/// V2-4 E7: the messages of a WebSocket ([source]: `String` or bytes) sent as
/// `tool.ws.msg` pieces of at most [kToolMaxChunkBytes], the last with
/// `fin`, within [window] and as [pacer] allows. While a message waits to go
/// it stops reading [source]. A message over [maxMessage] calls [onTooBig]
/// (the caller closes with 1009). [onDone]: the source ended and everything
/// went out.
final class ToolWsOut {
  ToolWsOut({
    required this.id,
    required Stream<Object?> source,
    required this.window,
    required this.pacer,
    required void Function(ToolMessage message) send,
    this.maxMessage = kToolMaxWsMessageBytes,
    this.onTooBig,
    this.onDone,
  }) : _source = source,
       _send = send;

  final int id;
  final ToolSendWindow window;
  final ToolPacer pacer;
  final void Function(ToolMessage message) _send;
  final Stream<Object?> _source;
  final int maxMessage;
  final void Function()? onTooBig;
  final void Function()? onDone;

  final _messages = Queue<({Uint8List bytes, bool text})>();
  int _offset = 0; // into the first message
  int _queued = 0;
  StreamSubscription<Object?>? _subscription;
  bool _paused = false;
  bool _asked = false;
  void Function()? _withdraw;
  bool _ended = false;
  bool _stopped = false;

  void start() {
    _subscription = _source.listen(
      _onMessage,
      onError: (Object _) {},
      onDone: () {
        _ended = true;
        _pump();
      },
    );
  }

  void _onMessage(Object? message) {
    if (_stopped) return;
    final text = message is String;
    final bytes = switch (message) {
      final String s => utf8.encode(s),
      final Uint8List b => b,
      final List<int> b => Uint8List.fromList(b),
      _ => null,
    };
    if (bytes == null) return;
    if (bytes.length > maxMessage) {
      stop();
      onTooBig?.call();
      return;
    }
    _messages.add((bytes: bytes, text: text));
    _queued += bytes.length;
    if (_queued >= kToolMaxChunkBytes && !_paused) {
      _paused = true;
      _subscription?.pause();
    }
    _pump();
  }

  bool onAck(int total) {
    if (!window.onAck(total)) return false;
    _pump();
    return true;
  }

  int get _nextSize =>
      min(_messages.first.bytes.length - _offset, kToolMaxChunkBytes);

  void _pump() {
    if (_stopped || _asked) return;
    if (_messages.isEmpty) {
      if (_ended) {
        _stopped = true;
        onDone?.call();
      }
      return;
    }
    if (!window.canSend(_nextSize)) {
      window._waitForCredit(_pump);
      return;
    }
    _asked = true;
    final withdraw = pacer.acquire(_sendOne);
    if (_asked) _withdraw = withdraw; // not granted at once
  }

  int? _sendOne() {
    _asked = false;
    _withdraw = null;
    if (_stopped || _messages.isEmpty) return null;
    final size = _nextSize;
    if (!window.canSend(size)) {
      scheduleMicrotask(_pump);
      return null;
    }
    final message = _messages.first;
    final piece = Uint8List.sublistView(message.bytes, _offset, _offset + size);
    _offset += size;
    final fin = _offset == message.bytes.length;
    if (fin) {
      _messages.removeFirst();
      _offset = 0;
    }
    _queued -= size;
    window.onSent(size);
    _send(ToolWsMessage(id: id, data: piece, text: message.text, fin: fin));
    if (_paused && _queued < kToolMaxChunkBytes) {
      _paused = false;
      _subscription?.resume();
    }
    scheduleMicrotask(_pump);
    return size;
  }

  /// Stops reading and sending (the window still counts what was sent).
  void stop() {
    _stopped = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    unawaited(_subscription?.cancel());
  }

  /// [stop], and the window no longer counts it.
  void cancel() {
    stop();
    window.close();
  }

  /// Stops sending but keeps reading [source], dropping what comes, so a
  /// closing WebSocket can finish its handshake.
  void discard() {
    _stopped = true;
    _asked = false;
    _withdraw?.call();
    _withdraw = null;
    window._stopWaiting(_pump);
    _messages.clear();
    _queued = 0;
    if (_paused) {
      _paused = false;
      _subscription?.resume();
    }
  }
}

/// V2-4 E7: WebSocket pieces as they arrive (`tool.ws.msg`), put together and
/// written in order with [write] (`ws.addStream(Stream.value(message))`,
/// which completes once the socket took it). Bytes are acknowledged
/// ([onConsumed]) while nothing waits to be written; while a message waits,
/// what follows is held unacknowledged, so the sender stops after its
/// window. A message over [maxMessage], a piece that changes the kind of
/// its message, or more in flight than [window]: [add] says no.
final class ToolWsIn {
  ToolWsIn({
    required Future<void> Function(Object message) write,
    required void Function(int total) onConsumed,
    this.window = kToolStreamWindow,
    this.maxMessage = kToolMaxWsMessageBytes,
  }) : _write = write,
       _onConsumed = onConsumed;

  final Future<void> Function(Object message) _write;
  final void Function(int total) _onConsumed;
  final int window;
  final int maxMessage;
  final _parts = BytesBuilder(copy: false);
  bool _text = false;
  final _queue = Queue<Object>();
  Future<void>? _writing;
  int _received = 0;
  int _consumed = 0;
  bool _failed = false;
  Completer<void>? _idle;

  /// Whether a message is still waiting to be written (or being written).
  bool get busy => _writing != null || _queue.isNotEmpty;

  /// Completes once everything that arrived was written.
  Future<void> get idle {
    if (!busy) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  bool add(ToolWsMessage piece) {
    if (_failed) return false;
    _received += piece.data.length;
    if (_received - _consumed > window) return false;
    if (_parts.isEmpty) {
      _text = piece.text;
    } else if (piece.text != _text) {
      return false;
    }
    if (_parts.length + piece.data.length > maxMessage) return false;
    _parts.add(piece.data);
    if (piece.fin) {
      final bytes = _parts.takeBytes();
      _queue.add(_text ? utf8.decode(bytes, allowMalformed: true) : bytes);
    }
    _writeNext();
    _report();
    return true;
  }

  void _writeNext() {
    if (_writing != null || _queue.isEmpty || _failed) return;
    _writing = _write(_queue.removeFirst()).then(
      (_) {
        _writing = null;
        _writeNext();
        _report();
      },
      onError: (Object _) {
        _writing = null;
        _failed = true;
        _queue.clear();
        _report();
      },
    );
  }

  void _report() {
    if (busy) return;
    final idle = _idle;
    _idle = null;
    idle?.complete();
    if (_failed || _consumed == _received) return;
    _consumed = _received;
    _onConsumed(_consumed);
  }
}

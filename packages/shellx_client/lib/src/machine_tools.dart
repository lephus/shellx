import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';

/// V2-4 §4.2: one tool a computer lets this phone open.
final class ToolInfo {
  const ToolInfo({
    required this.id,
    required this.name,
    required this.ws,
    required this.port,
    required this.path,
    required this.group,
  });

  final String id;
  final String name;

  /// The workspace's name ("shop-web").
  final String ws;
  final int port;

  /// The start page (path and query).
  final String path;

  /// The workspace's key: tools of one group are served together (E4).
  final String group;

  @override
  bool operator ==(Object other) =>
      other is ToolInfo &&
      other.id == id &&
      other.name == name &&
      other.ws == ws &&
      other.port == port &&
      other.path == path &&
      other.group == group;

  @override
  int get hashCode => Object.hash(id, name, ws, port, path, group);

  @override
  String toString() => 'ToolInfo(…)';
}

/// V2-4 §4.2: what `tool.list.result` says. [available] is false while the
/// computer has no list yet ("Mở ShellX trên máy tính để dùng tool.").
final class ToolListing {
  const ToolListing({this.available = true, this.tools = const []});

  final bool available;
  final List<ToolInfo> tools;

  /// Never throws: an entry this version cannot read is left out.
  static ToolListing fromBody(Uint8List body, {required bool available}) {
    final json = _json(body);
    final list = json is Map ? json['tools'] : null;
    return ToolListing(
      available: available,
      tools: [
        if (list is List)
          for (final entry in list) ?_tool(entry),
      ],
    );
  }

  static ToolInfo? _tool(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name'];
    final ws = entry['ws'];
    final port = entry['port'];
    final path = entry['path'];
    final group = entry['group'];
    if (id is! String || name is! String || ws is! String) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    if (path is! String || !isToolTarget(path) || group is! String) {
      return null;
    }
    return ToolInfo(
      id: id,
      name: name,
      ws: ws,
      port: port,
      path: path,
      group: group,
    );
  }

  @override
  String toString() => 'ToolListing(…)';
}

/// V2-4 E4: one tool a phone serves while a tool is open, from
/// `tool.opened`'s body (the opened tool first).
final class ToolServing {
  const ToolServing({required this.id, required this.port, required this.path});
  final String id;
  final int port;
  final String path;

  /// Never throws; empty when [body] is not readable.
  static List<ToolServing> fromBody(Uint8List? body) {
    final json = body == null ? null : _json(body);
    final list = json is Map ? json['tools'] : null;
    return [
      if (list is List)
        for (final entry in list)
          if (entry is Map &&
              entry['id'] is String &&
              entry['port'] is int &&
              (entry['port'] as int) >= 1 &&
              (entry['port'] as int) <= 65535 &&
              entry['path'] is String &&
              isToolTarget(entry['path'] as String))
            ToolServing(
              id: entry['id'] as String,
              port: entry['port'] as int,
              path: entry['path'] as String,
            ),
    ];
  }

  @override
  String toString() => 'ToolServing(…)';
}

Object? _json(Uint8List body) {
  try {
    return jsonDecode(utf8.decode(body));
  } on FormatException {
    return null;
  }
}

/// What a stream of a tool page hears from the computer. Implementations must
/// not throw: [MachineTools] isolates every call (a throw is dropped, never
/// logged), so one stream cannot take the channel's other traffic down.
abstract interface class ToolStreamListener {
  void onResponse(ToolResponse message);
  void onData(ToolData message);
  void onWsMessage(ToolWsMessage message);

  /// The computer took [total] bytes of what this phone sent.
  void onAck(int total);

  /// The computer ended the stream (after this nothing more comes for it).
  void onEnd(ToolEnd message);

  /// The channel is gone: the stream is over.
  void onLost();
}

/// Runs [call] on [listener] (if any) so that a throw ends only that call: a
/// stream must neither stop the rest of the sealed batch it heard this in
/// (terminal output and AI follow) nor abort a channel loss, which would leave
/// the machine half torn down. The error is dropped, never printed, logged or
/// passed to the zone: it may carry content (E18), as every error on the
/// client's inbox chain is dropped.
void _tell(
  ToolStreamListener? listener,
  void Function(ToolStreamListener listener) call,
) {
  if (listener == null) return;
  try {
    call(listener);
  } catch (_) {
    // Dropped on purpose, see above.
  }
}

/// An open waiting its turn ([MachineTools.acquireOpen]).
final class _OpenWait {
  _OpenWait(this.send);
  final void Function() send;
}

/// V2-4 E8: tool frames per second this phone sends at most (of the relay's
/// 500 per device), and at once.
const int kToolPhoneFramesPerSecond = 100;
const int kToolPhoneFrameBurst = 10;

/// V2-4 I3 (final review): the stream opens (`tool.open`, and `tool.req` for
/// HTTP and WebSocket alike) this phone sends at once, then a second, granted
/// in order. The computer keeps E10 as written: past 120 opens at once and
/// 60 a second it answers `busy`, a 503 for the page. So the phone paces its
/// own and a request waits its turn on the phone (the web view's request
/// stays pending): E20 expects a dev page of many modules to load slowly the
/// first time, never to break. These numbers sit under E10's to leave room
/// for transit bunching (opens sent apart may reach the computer together).
const int kToolPhoneOpenBurst = 100;
const int kToolPhoneOpensPerSecond = 50;

/// The personal web tools of one machine (V2-4): their list, opening one,
/// the streams of the open tool page, and the tool outbox (E8) every `tool.*`
/// message goes through: collected for [flushInterval], split with
/// [splitIntoBatches], at most [kToolPhoneFramesPerSecond] frames a second;
/// acknowledgements of every stream in one `tool.ack` per 50 ms. Every stream
/// open waits its turn ([acquireOpen], I3). Part of [MachineClient]. Never
/// logs what it carries.
final class MachineTools {
  @internal
  MachineTools({
    required bool Function(List<AppMessage> messages) send,
    required Future<void> Function() connect,
    required Duration timeout,
    this.flushInterval = const Duration(milliseconds: 16),
    int framesPerSecond = kToolPhoneFramesPerSecond,
    int frameBurst = kToolPhoneFrameBurst,
  }) : _sendRaw = send,
       _connect = connect,
       _timeout = timeout,
       _frameEvery = Duration(microseconds: 1000000 ~/ framesPerSecond),
       _frameBurst = frameBurst,
       _frames = frameBurst {
    acks = ToolAckBook(enqueue);
  }

  final bool Function(List<AppMessage>) _sendRaw;
  final Future<void> Function() _connect;
  final Duration _timeout;
  final Duration flushInterval;

  /// One frame token comes back this often (E8: 100 a second), up to
  /// [_frameBurst].
  final Duration _frameEvery;
  final int _frameBurst;
  bool? _supported;
  ToolListing? _listing;
  final _listings = StreamController<ToolListing>.broadcast(sync: true);
  final _links = StreamController<bool>.broadcast(sync: true);
  var _watching = false;
  var _connected = false;
  var _disposed = false;
  final _opens = <int, Completer<ToolOpened>>{};
  var _nextRid = 1;
  var _nextStream = 1;
  final _streams = <int, ToolStreamListener>{};

  /// Phone → desktop bytes in flight over all streams (E7).
  ToolCredit credit = ToolCredit();

  /// What this phone took of the computer's bodies and messages.
  late final ToolAckBook acks;

  // The outbox.
  final _outbox = <AppMessage>[];
  Timer? _flush;
  int _frames;
  Timer? _refill;

  // The stream opens (I3): one token comes back every [_openEvery], up to
  // [kToolPhoneOpenBurst]; the opens waiting for one, in order.
  static const _openEvery = Duration(
    microseconds: 1000000 ~/ kToolPhoneOpensPerSecond,
  );
  int _opensLeft = kToolPhoneOpenBurst;
  Timer? _openRefill;
  final _openWaits = Queue<_OpenWait>();

  /// Pages keeping the channel: an open tool page wants it back after a loss.
  int _holders = 0;

  /// Whether the computer has tools for phones (`tools` in
  /// `session.list.result`); null before the first desktop list.
  bool? get supported => _supported;

  ToolListing? get listing => _listing;

  /// Every list as it comes (the first answer, then each change).
  Stream<ToolListing> get listings => _listings.stream;

  /// True when a channel is installed, false when it is lost.
  Stream<bool> get links => _links.stream;

  bool get connected => _connected;

  /// The list is watched or a tool page is open: a lost channel must come
  /// back even without a terminal tab.
  bool get wantsChannel => _watching || _holders > 0;

  /// Keeps the list current: asks now (connecting first when there is no
  /// channel) and again on every new channel.
  Future<void> watch() async {
    _watching = true;
    if (!enqueue(const ToolList())) await _connect(); // channelReady asks
  }

  /// The inverse of [watch]; a no-op when nothing is watched.
  void unwatch() => _watching = false;

  /// A tool page holds the channel, and the list (its changes tell the page
  /// its tool was turned off or deleted, E16), until the returned function is
  /// called.
  void Function() hold() {
    _holders++;
    if (_holders == 1 && !_watching) enqueue(const ToolList());
    var held = true;
    return () {
      if (!held) return;
      held = false;
      _holders--;
    };
  }

  /// `tool.open` [tool] (an id from the list): the computer checks its flag
  /// and tries its port. Connects first, then waits its turn like every
  /// stream open ([acquireOpen]); throws [MachineConnectionException] like
  /// every request.
  Future<ToolOpened> open(String tool) async {
    await _connect();
    final rid = _nextRid++;
    final done = _opens[rid] = Completer<ToolOpened>();
    final withdraw = acquireOpen(() {
      if (!identical(_opens[rid], done)) return; // over meanwhile
      if (!enqueue(ToolOpen(rid: rid, tool: tool))) {
        _opens.remove(rid);
        done.completeError(
          const MachineConnectionException(
            MachineConnectionFailure.agentOffline,
          ),
        );
      }
    });
    return done.future.timeout(
      _timeout,
      onTimeout: () {
        withdraw();
        _opens.remove(rid);
        throw const MachineConnectionException(
          MachineConnectionFailure.timeout,
        );
      },
    );
  }

  /// I3: [send] runs once this phone may open one more stream (`tool.open`,
  /// `tool.req`): at once when a token is there and no open waits, else in
  /// turn, [kToolPhoneOpensPerSecond] a second after the first
  /// [kToolPhoneOpenBurst]. The returned function withdraws an open not
  /// granted yet (its stream ended meanwhile: its message never goes). A
  /// lost channel drops every open that waits, and the next channel starts
  /// with every token (the computer forgets this phone's budget too).
  void Function() acquireOpen(void Function() send) {
    if (_openWaits.isEmpty && _opensLeft > 0) {
      _takeOpen();
      send();
      return () {};
    }
    final wait = _OpenWait(send);
    _openWaits.add(wait);
    return () => _openWaits.remove(wait);
  }

  void _takeOpen() {
    _opensLeft--;
    _openRefill ??= Timer.periodic(_openEvery, (_) {
      _opensLeft++;
      while (_opensLeft > 0 && _openWaits.isNotEmpty) {
        _opensLeft--;
        final wait = _openWaits.removeFirst();
        // Isolated, as a stream's calls are ([_tell]): one open that throws
        // must not hold back the others. Dropped, never logged (E18).
        try {
          wait.send();
        } catch (_) {
          // Dropped on purpose, see above.
        }
      }
      if (_opensLeft >= kToolPhoneOpenBurst) {
        _openRefill?.cancel();
        _openRefill = null;
      }
    });
  }

  /// A new stream number on this channel.
  int newStreamId() => _nextStream++;

  /// The computer's messages for stream [id] go to [listener] until it ends,
  /// the channel goes, or [release].
  void listen(int id, ToolStreamListener listener) => _streams[id] = listener;

  void release(int id) {
    _streams.remove(id);
    acks.forget(id);
  }

  /// Queues [message] in the tool outbox. False (nothing queued) without a
  /// channel, or for a message that would not fit one sealed batch (it would
  /// drop the channel, RF 1).
  bool enqueue(ToolMessage message) {
    if (!_connected || _disposed) return false;
    if (encodeBatch([message]).length > kMaxSealedBatchBytes) return false;
    _outbox.add(message);
    _flush ??= Timer(flushInterval, _send);
    return true;
  }

  void _send() {
    _flush = null;
    if (!_connected || _outbox.isEmpty) return;
    final batches = splitIntoBatches(_outbox);
    _outbox.clear();
    var sent = 0;
    for (final batch in batches) {
      if (_frames < 1) break;
      if (!_sendRaw(batch)) {
        sent = batches.length; // the channel is gone: drop the rest
        break;
      }
      _spend();
      sent++;
    }
    // Over the frame budget: the rest waits, in order, for the next token.
    _outbox.addAll([for (final batch in batches.skip(sent)) ...batch]);
  }

  void _spend() {
    _frames--;
    _refill ??= Timer.periodic(_frameEvery, (_) {
      _frames++;
      if (_frames >= _frameBurst) {
        _refill?.cancel();
        _refill = null;
      }
      if (_outbox.isNotEmpty && _flush == null) _send();
    });
  }

  // ------------------------------------------------- from MachineClient --

  /// The answer to a `session.list {desktop: true}`.
  @internal
  void noteListResult(SessionListResult result) {
    final tools = result.tools;
    _supported = tools != null && tools >= 1;
  }

  @internal
  void handle(ToolMessage message) {
    if (_disposed) return;
    switch (message) {
      case ToolListResult(:final available, :final body):
        _supported = true;
        final listing = ToolListing.fromBody(body, available: available);
        _listing = listing;
        _listings.add(listing);
      case ToolOpened(:final rid):
        _opens.remove(rid)?.complete(message);
      case ToolResponse(:final id):
        _tell(_streams[id], (s) => s.onResponse(message));
      case ToolData(:final id):
        _tell(_streams[id], (s) => s.onData(message));
      case ToolWsMessage(:final id):
        _tell(_streams[id], (s) => s.onWsMessage(message));
      case ToolAck(:final acks):
        for (var i = 0; i + 1 < acks.length; i += 2) {
          final total = acks[i + 1];
          _tell(_streams[acks[i]], (s) => s.onAck(total));
        }
      case ToolEnd(:final id):
        final listener = _streams.remove(id);
        acks.forget(id);
        _tell(listener, (s) => s.onEnd(message));
      case ToolList() || ToolOpen() || ToolClose() || ToolRequest():
        break; // a phone's own kinds never come from the computer
    }
  }

  @internal
  void channelReady() {
    if (_disposed) return;
    _connected = true;
    if (wantsChannel) enqueue(const ToolList());
    _links.add(true);
  }

  /// The channel is gone: opens in flight fail (never sent again), opens
  /// waiting their turn are dropped, every stream ends, nothing queued goes
  /// out.
  @internal
  void channelLost() {
    _connected = false;
    _flush?.cancel();
    _flush = null;
    _refill?.cancel();
    _refill = null;
    _frames = _frameBurst;
    _openRefill?.cancel();
    _openRefill = null;
    _opensLeft = kToolPhoneOpenBurst;
    _openWaits.clear();
    _outbox.clear();
    acks.clear();
    credit = ToolCredit();
    final opens = [..._opens.values];
    _opens.clear();
    for (final open in opens) {
      open.completeError(
        const MachineConnectionException(MachineConnectionFailure.agentOffline),
      );
    }
    final streams = [..._streams.values];
    _streams.clear();
    for (final stream in streams) {
      _tell(stream, (s) => s.onLost());
    }
    if (!_disposed) _links.add(false);
  }

  @internal
  void dispose() {
    if (_disposed) return;
    channelLost();
    _disposed = true;
    unawaited(_listings.close());
    unawaited(_links.close());
  }
}

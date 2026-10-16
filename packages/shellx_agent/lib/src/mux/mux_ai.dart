import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../ai/ai_endpoint.dart';
import '../ai/ai_phone_hub.dart';
import '../session/agent_sessions.dart';
import 'mux_messages.dart';
import 'remote_local_sessions.dart';

/// [message] as the service passes it on: as it came when it was read from
/// the wire ([AiMessage.wire], V2-2b B2), keys this version does not know
/// included.
MuxMessage _carry(String type, String mobileId, AiMessage message) =>
    MuxMessage(type, fields: {'m': mobileId, 'b': encodeCbor(message.wire)});

/// The `ai.*` message in [m]'s `b` (an [AiRaw] for a kind this version does
/// not know); null when it is not one, or a malformed one of a kind this
/// version reads.
AiMessage? _carried(MuxMessage m) {
  final bytes = m.get<Uint8List>('b');
  if (bytes == null) return null;
  try {
    final map = decodeCbor(bytes);
    if (map is! Map<Object?, Object?>) return null;
    final message = AppMessage.fromMap(map);
    return message is AiMessage ? message : null;
  } on FormatException {
    return null;
  }
}

/// Which way a kind goes: true for the kinds a desktop sends to a phone,
/// false for the kinds a phone sends; null for a kind this version does not
/// know ([AiRaw], V2-2b B2), which goes the way it came. Exhaustive: a new
/// kind must be placed here.
bool? _towardsPhone(AiMessage m) => switch (m) {
  AiListResult() ||
  AiSnapshot() ||
  AiUpdate() ||
  AiClosed() ||
  AiResult() => true,
  AiList() ||
  AiAttach() ||
  AiDetach() ||
  AiAck() ||
  AiEarlier() ||
  AiPrompt() ||
  AiAnswer() ||
  AiCancel() ||
  AiForceStop() ||
  AiUnqueue() ||
  AiOpen() ||
  AiConfigGet() ||
  AiConfigSet() ||
  AiBlob() ||
  AiFiles() ||
  AiItemPart() ||
  AiHistory() ||
  AiFolder() ||
  AiChanges() ||
  AiDiff() ||
  AiRevert() => false,
  AiRaw() => null,
};

/// The longest session id the service keeps for a phone: the hub's own limit
/// (`AiPhoneHub` answers none longer, and the ones it makes are far shorter).
const int _maxSidLength = 256;

/// V2-2 D1, background service side: phones' `ai.*` messages go to the
/// attached window that serves AI (`ai.in`), its answers come back
/// (`ai.out`). Without such a window phones get [aiUnavailableReply]; when
/// it goes, every phone that listed hears `available: false` and every
/// mirror closes with `desktop_closed`. When a window starts serving, the
/// phones that listed are listed again for it.
///
/// Only the kinds that belong to a direction travel it: a desktop → phone
/// kind from a phone, a phone → desktop kind from the window, and a message
/// over one sealed batch are dropped, never sent (a batch too big would
/// drop the phone's whole channel). Since V2-2b (B2) a kind this version
/// does not know goes the way it came, and every message goes on as it came
/// ([AiMessage.wire]): a later addition needs only the window.
final class MuxAiForwarder implements AiEndpoint {
  MuxAiForwarder({this.onPush});

  /// `ai.push` from the window: the service's own notifications send it.
  final void Function(AiPush push)? onPush;

  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  Object? _owner;
  void Function(MuxMessage message)? _ui;
  final _listing = <String>{};
  final _attached = <String, Set<String>>{};

  /// A window serves AI now.
  bool get serving => _ui != null;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  /// The window behind [owner] serves AI from now on (`ai.serve`).
  void serve(Object owner, void Function(MuxMessage message) send) {
    _owner = owner;
    _ui = send;
    for (final mobileId in _listing) {
      send(_carry(MuxType.aiIn, mobileId, const AiList()));
    }
  }

  /// [owner]'s window went away.
  void unserve(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _ui = null;
    for (final mobileId in _listing) {
      _emit(mobileId, AiListResult(available: false, body: emptyAiListingBody));
    }
    for (final MapEntry(key: mobileId, value: sids) in _attached.entries) {
      for (final sid in sids) {
        _emit(mobileId, AiClosed(sid: sid, reason: 'desktop_closed'));
      }
    }
    _attached.clear();
  }

  /// `ai.out` or `ai.push` from [owner]'s window. Only desktop → phone
  /// types, and kinds this version does not know (B2), that fit one sealed
  /// batch are passed on; anything else is dropped, never sent (a batch too
  /// big would drop the phone's channel).
  void fromUi(Object owner, MuxMessage m) {
    if (!identical(_owner, owner)) return;
    switch (m.type) {
      case MuxType.aiOut:
        final mobileId = m.get<String>('m');
        final message = _carried(m);
        if (mobileId == null || message == null) return;
        if (_towardsPhone(message) == false) return;
        if (message is AiClosed) _attached[mobileId]?.remove(message.sid);
        _emit(mobileId, message);
      case MuxType.aiPush:
        final push = AiPush.fromFields(m.fields);
        if (push == null) return;
        try {
          onPush?.call(push);
        } on Object {
          // A push that cannot be sent is lost; an error here would be an
          // uncaught one in the link's message handler.
        }
    }
  }

  @override
  void handle(String mobileId, AiMessage message) {
    // The router passes every kind: a phone does not send the desktop's (the
    // hub ignores them too), so they go nowhere.
    if (_towardsPhone(message) == true) return;
    final ui = _ui;
    switch (message) {
      case AiList():
        _listing.add(mobileId);
      // Only a mirror the window knows of is open; without a window the
      // attach is answered "closed" below. A session id longer than the
      // hub's limit is none it made and none it answers: it is passed on, not
      // kept (a phone cannot make the service remember what it likes).
      case AiAttach(:final sid) when ui != null:
        if (sid.length <= _maxSidLength) (_attached[mobileId] ??= {}).add(sid);
      case AiDetach(:final sid):
        _attached[mobileId]?.remove(sid);
      default:
        break;
    }
    if (ui != null) {
      ui(_carry(MuxType.aiIn, mobileId, message));
      return;
    }
    final reply = aiUnavailableReply(message);
    if (reply != null) _emit(mobileId, reply);
  }

  @override
  void phoneGone(String mobileId) {
    _listing.remove(mobileId);
    _attached.remove(mobileId);
    _ui?.call(MuxMessage(MuxType.aiGone, fields: {'m': mobileId}));
  }

  @override
  void allPhonesGone() {
    _listing.clear();
    _attached.clear();
    _ui?.call(const MuxMessage(MuxType.aiGone));
  }

  /// Every message to a phone goes through here: one over a sealed batch
  /// (the echo of a long session id, a window's oversize message) would make
  /// `SecureChannel.seal` throw and drop the channel, so it is not sent.
  void _emit(String mobileId, AiMessage message) {
    if (encodeBatch([message]).length > kMaxSealedBatchBytes) return;
    _out.add(OutboundMessage(mobileId, message));
  }
}

/// V2-2 D1, window side, in background-service mode: the service's `ai.in`
/// and `ai.gone` go to [hub]; the hub's messages go back as `ai.out`. Tells
/// the service it serves AI (`ai.serve`) once listening.
final class MuxAiBinding {
  MuxAiBinding(this.client, this.hub) {
    _events = client.events.listen(_onEvent);
    _out = hub.outbound.listen((o) {
      final message = o.message;
      client.send(MuxType.aiOut, {
        'm': o.mobileId,
        'b': encodeCbor(message is AiMessage ? message.wire : message.toMap()),
      });
    });
    client.send(MuxType.aiServe);
  }

  final MuxClient client;
  final AiEndpoint hub;
  late final StreamSubscription<MuxMessage> _events;
  late final StreamSubscription<OutboundMessage> _out;

  void _onEvent(MuxMessage m) {
    switch (m.type) {
      case MuxType.aiIn:
        final mobileId = m.get<String>('m');
        final message = _carried(m);
        if (mobileId != null && message != null) hub.handle(mobileId, message);
      case MuxType.aiGone:
        final mobileId = m.get<String>('m');
        if (mobileId == null) {
          hub.allPhonesGone();
        } else {
          hub.phoneGone(mobileId);
        }
    }
  }

  /// The link is gone or replaced: the phones it carried are gone too (at
  /// once, before a new link's phones arrive).
  Future<void> dispose() {
    hub.allPhonesGone();
    return Future.wait([_events.cancel(), _out.cancel()]);
  }
}

/// [AiPushSink] of a window in background-service mode: the service sends
/// the push with its own account (`ai.push`).
AiPushSink muxAiPushSink(MuxClient client) =>
    (push) => client.send(MuxType.aiPush, push.toFields());

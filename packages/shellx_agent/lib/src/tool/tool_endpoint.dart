import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';

/// V2-4 E5: where the `tool.*` messages of phones go, and where the answers
/// come from. The process that holds the relay serves them with a
/// `ToolProxy` (the window in-process, the background service otherwise);
/// the session router only routes.
abstract interface class ToolEndpoint {
  /// Messages to phones, in order (a synchronous broadcast stream: a
  /// listener must not call back into the endpoint from its callback).
  Stream<OutboundMessage> get outbound;

  /// Whether this process serves tools to phones (E6: only then does
  /// `session.list.result` carry `tools`).
  bool get serving;

  /// One `tool.*` message from phone [mobileId] (paired and trusted: only an
  /// established channel delivers messages). Returns at once: every network
  /// step runs in the background (the agent handles one message at a time).
  void handle(String mobileId, ToolMessage message);

  /// The channel to [mobileId] is gone, or the phone was revoked.
  void phoneGone(String mobileId);

  /// Every phone is gone (the relay link stopped).
  void allPhonesGone();
}

/// The list body when nobody serves tools.
final Uint8List emptyToolListingBody = Uint8List.fromList(
  utf8.encode('{"v":1,"tools":[]}'),
);

/// What a desktop answers when no proxy serves tools (V2-4 E5): the list is
/// unavailable, an open and a stream end `unavailable`. Null for messages
/// that need no answer.
ToolMessage? toolUnavailableReply(ToolMessage message) => switch (message) {
  ToolList() => ToolListResult(available: false, body: emptyToolListingBody),
  ToolOpen(:final rid) => ToolOpened(
    rid: rid,
    ok: false,
    code: ToolCode.unavailable,
  ),
  ToolRequest(:final id) => ToolEnd(id: id, code: ToolCode.unavailable),
  _ => null,
};

/// The router's [ToolEndpoint] for the life of a process (V2-4 E5): forwards
/// to [target]; without one it is not [serving] and answers
/// [toolUnavailableReply].
final class ToolEndpointSlot implements ToolEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  ToolEndpoint? _target;
  StreamSubscription<OutboundMessage>? _forward;

  ToolEndpoint? get target => _target;

  set target(ToolEndpoint? endpoint) {
    if (identical(endpoint, _target)) return;
    unawaited(_forward?.cancel());
    _target = endpoint;
    _forward = endpoint?.outbound.listen(_out.add);
  }

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  bool get serving => _target?.serving ?? false;

  @override
  void handle(String mobileId, ToolMessage message) {
    final target = _target;
    if (target != null) return target.handle(mobileId, message);
    final reply = toolUnavailableReply(message);
    if (reply != null) _out.add(OutboundMessage(mobileId, reply));
  }

  @override
  void phoneGone(String mobileId) => _target?.phoneGone(mobileId);

  @override
  void allPhonesGone() => _target?.allPhonesGone();
}

import 'dart:async';

import 'package:shellx_ai/remote.dart';
import 'package:shellx_core/shellx_core.dart';

import '../session/agent_sessions.dart';

/// V2-2 D1: where the `ai.*` messages of phones go, and where the answers
/// come from. The window's [AiPhoneHub] (the process with the AI tabs)
/// implements it; in the background service [MuxAiForwarder] passes them
/// to the attached window. The session router only routes.
abstract interface class AiEndpoint {
  /// Messages to phones, in order (a synchronous broadcast stream: a
  /// listener must not call back into the endpoint from its callback).
  Stream<OutboundMessage> get outbound;

  /// One `ai.*` message from phone [mobileId] (paired and trusted: only an
  /// established channel delivers messages).
  void handle(String mobileId, AiMessage message);

  /// The channel to [mobileId] is gone, or the phone was revoked.
  void phoneGone(String mobileId);

  /// Every phone is gone (the relay link stopped).
  void allPhonesGone();
}

/// The listing body when no window serves AI.
final emptyAiListingBody = encodeBody(const AiListing().toJson());

/// What a desktop answers when nobody serves AI (V2-2 D1): the list is
/// unavailable, an attach is closed with [reason], a request fails
/// `unavailable`. Null for messages that need no answer.
AiMessage? aiUnavailableReply(
  AiMessage message, {
  String reason = 'unavailable',
}) => switch (message) {
  AiList() => AiListResult(available: false, body: emptyAiListingBody),
  AiAttach(:final sid) => AiClosed(sid: sid, reason: reason),
  AiPrompt(:final rid) ||
  AiAnswer(:final rid) ||
  AiCancel(:final rid) ||
  AiForceStop(:final rid) ||
  AiUnqueue(:final rid) ||
  AiOpen(:final rid) => AiResult(rid: rid, ok: false, code: 'unavailable'),
  _ => null,
};

/// The router's [AiEndpoint] in a process whose window builds its hub
/// later (V2-2 D1): forwards to [target]; without one it answers
/// [aiUnavailableReply].
final class AiEndpointSlot implements AiEndpoint {
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  AiEndpoint? _target;
  StreamSubscription<OutboundMessage>? _forward;

  AiEndpoint? get target => _target;

  /// Every phone hears of the change through its next request.
  set target(AiEndpoint? endpoint) {
    unawaited(_forward?.cancel());
    _target = endpoint;
    _forward = endpoint?.outbound.listen(_out.add);
  }

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    final target = _target;
    if (target != null) return target.handle(mobileId, message);
    final reply = aiUnavailableReply(message);
    if (reply == null) return;
    // The reply may repeat the phone's session id: one over a sealed batch
    // would make `SecureChannel.seal` throw and drop the whole channel, so it
    // is not sent.
    if (encodeBatch([reply]).length > kMaxSealedBatchBytes) return;
    _out.add(OutboundMessage(mobileId, reply));
  }

  @override
  void phoneGone(String mobileId) => _target?.phoneGone(mobileId);

  @override
  void allPhonesGone() => _target?.allPhonesGone();
}

import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import 'drive.dart';
import 'harness.dart';

/// A desktop that says what a test scripts (V2-2b): its listing offers
/// [features]; every `ai.*` message the phone sends is recorded, and a
/// request is answered with what [answer] returns — or held when it returns
/// null (the test answers it later with [say]).
final class ScriptedDesktop implements AiEndpoint {
  ScriptedDesktop({this.features = const {}});

  final Set<String> features;
  final _out = StreamController<OutboundMessage>.broadcast(sync: true);
  final received = <AiMessage>[];
  AiMessage? Function(AiMessage message)? answer;

  @override
  Stream<OutboundMessage> get outbound => _out.stream;

  @override
  void handle(String mobileId, AiMessage message) {
    received.add(message);
    if (message is AiList) {
      say(
        AiListResult(
          available: true,
          body: encodeBody(AiListing(features: features).toJson()),
        ),
      );
      return;
    }
    final reply = answer?.call(message);
    if (reply != null) say(reply);
  }

  @override
  void phoneGone(String mobileId) {}

  @override
  void allPhonesGone() {}

  void say(AiMessage message) => _out.add(OutboundMessage(phoneId, message));

  List<T> got<T extends AiMessage>() => received.whereType<T>().toList();
}

/// The phone's AI of [h] once it knows what a V2-2b request needs (B1): the
/// protocol (a desktop list) and the listing (watched).
MachineAi readyAi(Harness h) {
  final machine = h.phoneMachine;
  h.run(machine.listSessions(includeDesktop: true));
  h.run(machine.ai.watch());
  settle(h.async);
  return machine.ai;
}

import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';

final class FakeUiApi implements UiApi {
  final requests = <MuxMessage>[];
  final appNotices = <(String?, String)>[];
  final paneNotices = <(int, String?, String)>[];
  final eventsOut = StreamController<Map<String, Object?>>.broadcast();
  Set<int> livePanes = {12};
  Completer<void>? gate;

  /// Replaces the `ui.*` answer (to test oversized results).
  Map<String, Object?>? answer;

  /// The `isGone` of the last [handle] call.
  bool Function()? isGone;

  @override
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
    bool Function()? isGone,
  }) async {
    requests.add(request);
    this.isGone = isGone;
    await gate?.future;
    if (request.type == 'ui.fail') {
      throw const CliFailure('not_found', 'no pane p1');
    }
    return answer ?? {'echo': request.type};
  }

  @override
  Stream<Map<String, Object?>> events() => eventsOut.stream;

  @override
  Future<void> notifyApp({String? title, required String body}) async =>
      appNotices.add((title, body));

  @override
  bool notifyPane(int pane, {String? title, required String body}) {
    paneNotices.add((pane, title, body));
    return livePanes.contains(pane);
  }
}

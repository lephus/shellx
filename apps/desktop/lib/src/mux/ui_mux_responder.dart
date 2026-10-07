import 'dart:async';

import 'package:shellx_agent/shellx_agent.dart';

/// A5b D22: the window's side of the command line. The background service
/// forwards a `cli` client's `ui.*` request to the attached UI; this answers
/// it with the window's [UiApi] (the `UiCommandHandler`) and sends the
/// window's events (`ui.event`) the other way.
///
/// A request that arrives before the window is up waits for [bind] (A7 C1,
/// `attach` semantics), at most [attachWait], then fails as `busy`. Never
/// logs a request or an event.
final class UiMuxResponder {
  UiMuxResponder({this.attachWait = const Duration(seconds: 15)});

  /// A window that never attaches (a start that hangs) cannot hold a
  /// request open.
  final Duration attachWait;

  final _ready = Completer<UiApi>();
  StreamSubscription<Map<String, Object?>>? _events;

  /// The window is up: requests reach it, and its events go to [client].
  /// Again with the new client after the background service restarted.
  void bind(UiApi ui, MuxClient client) {
    if (!_ready.isCompleted) _ready.complete(ui);
    unawaited(_events?.cancel());
    _events = ui.events().listen(
      (event) => client.send(MuxType.uiEvent, event),
      onError: (Object _) {},
    );
  }

  /// [MuxClient.onRequest]. [CliFailure] becomes the `error` answer.
  Future<Map<String, Object?>> onRequest(MuxMessage request) async {
    final UiApi ui;
    try {
      ui = await _ready.future.timeout(attachWait);
    } on TimeoutException {
      throw const CliFailure('busy', 'ShellX is still starting');
    }
    return ui.handle(request);
  }

  Future<void> dispose() async => _events?.cancel();
}

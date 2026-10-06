import 'mux_messages.dart';

/// A refused CLI request: becomes `error{code, message?}` on the wire
/// (A7 D5).
final class CliFailure implements Exception {
  const CliFailure(this.code, [this.message]);
  final String code;
  final String? message;

  @override
  String toString() => 'CliFailure($code)';
}

/// A7 D3: what the window does for the CLI host. The host owns the wire,
/// the allowlist, the switch and the limits; this side owns the tabs.
abstract interface class UiApi {
  /// One `ui.*` request → result fields. Throws [CliFailure].
  /// [cancelled] completes when the asking client went away (D21: a
  /// `wait` stops then).
  Future<Map<String, Object?>> handle(
    MuxMessage request, {
    Future<void>? cancelled,
  });

  /// D24 events (already filtered to what the UI emits).
  Stream<Map<String, Object?>> events();

  /// D23 without a pane: system notification + "Dòng lệnh" panel entry.
  Future<void> notifyApp({String? title, required String body});

  /// D23 with a pane: `LocalSessions.notify`. False: no such session.
  bool notifyPane(int pane, {String? title, required String body});
}

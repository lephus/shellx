import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'session_manager.dart';

/// The terminal window's way into the agent's sessions (A1 spec §3.1). The
/// window never talks to `SessionManager` directly, so A5 can move the
/// sessions into a daemon behind this same interface.
abstract interface class LocalSessions {
  /// Listable sessions in creation order.
  List<SessionSummary> get sessions;

  /// Fires when [sessions] (or anything in a summary) changes.
  Stream<void> get changes;

  /// Starts a login shell in the home directory. Throws
  /// [SessionLimitException] or [SpawnFailedException].
  Future<int> open({required int cols, required int rows});

  /// One local viewer of session [id]. Throws [StateError] when there is no
  /// such session.
  LocalSessionView view(int id);

  /// Ends session [id] and its process tree (the desktop may close every
  /// session, A1 D4).
  void close(int id);
}

/// One local viewer of a session. It is not a phone: it has no send window
/// and never kicks a phone out (A1 D5).
abstract interface class LocalSessionView {
  int get id;

  /// What the ring buffer held when the view was made (at most 256 KiB).
  Uint8List get backlog;

  /// Live output after [backlog], buffered from the moment the view was
  /// made (single listener). Done once the session has ended.
  Stream<Uint8List> get output;

  /// Driver changes (A1 D6).
  Stream<DriverSide> get driver;

  /// The shell's exit code.
  Future<int> get exitCode;

  /// The session ended because it was closed (window, phone, revoke,
  /// quit), not on its own. Meaningful once [exitCode] has completed.
  bool get closedOnRequest;

  /// Keystrokes, paste, mouse reports: the desktop drives (unless the phone
  /// typed within the driver hold).
  void write(Uint8List data);

  /// Answers the window's terminal generates by itself (cursor position,
  /// device attributes): written only while the desktop drives, so the
  /// shell never gets two answers to one question.
  void reply(Uint8List data);

  /// The window's size for this session. The first size of a session the
  /// phone drives is only remembered (a tab being laid out is not the user
  /// asking for the terminal); later sizes make the desktop drive.
  void resize(int cols, int rows);

  /// Stops [output]; the session keeps running.
  void dispose();
}

/// The computer already has the maximum number of sessions (A1 D8).
final class SessionLimitException implements Exception {
  const SessionLimitException(this.max);
  final int max;
  @override
  String toString() => 'SessionLimitException: $max sessions are open';
}

/// The shell could not be started. [message] is the underlying error as
/// text (it never contains terminal output).
final class SpawnFailedException implements Exception {
  const SpawnFailedException(this.message);
  final String message;
  @override
  String toString() => 'SpawnFailedException: $message';
}

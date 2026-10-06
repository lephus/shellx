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

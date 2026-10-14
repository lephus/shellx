/// Runs async operations one at a time, in the order they were queued; a
/// failed operation does not stop the ones after it.
final class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

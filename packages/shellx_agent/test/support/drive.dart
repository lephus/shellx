import 'package:fake_async/fake_async.dart';

/// Advances fake time in 1 ms steps until [future] completes, then returns
/// its value (or rethrows its error). Fails after [limit] of fake time.
T drive<T>(
  FakeAsync async,
  Future<T> future, {
  Duration limit = const Duration(seconds: 60),
}) {
  var done = false;
  late T value;
  Object? error;
  StackTrace? stackTrace;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      stackTrace = s;
      done = true;
    },
  );
  var waited = Duration.zero;
  const step = Duration(milliseconds: 1);
  while (!done) {
    if (waited >= limit) {
      throw StateError('Future did not complete within $limit of fake time');
    }
    async.elapse(step);
    waited += step;
  }
  if (error != null) Error.throwWithStackTrace(error!, stackTrace!);
  return value;
}

/// Lets timers and microtasks run for [duration] of fake time.
void settle(
  FakeAsync async, [
  Duration duration = const Duration(milliseconds: 100),
]) {
  async.elapse(duration);
}

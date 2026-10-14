import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs [work] on [input] away from the UI isolate and returns its result
/// (smoothness: the frame budget). [work] must be a top-level or static
/// function and [input] sendable.
typedef OffThread = Future<R> Function<Q, R>(R Function(Q input) work, Q input);

Future<R> _onIsolate<Q, R>(R Function(Q input) work, Q input) =>
    Isolate.run(() => work(input));

/// Runs [work] right here: tests (a real isolate never runs under fake
/// async) and work too small to be worth a trip.
Future<R> inlineOffThread<Q, R>(R Function(Q input) work, Q input) async =>
    work(input);

/// Line diffs over 2 000 lines, project file indexes, big file reads.
final aiOffThreadProvider = Provider<OffThread>((ref) => _onIsolate);

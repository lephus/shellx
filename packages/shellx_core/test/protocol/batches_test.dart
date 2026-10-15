import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

OutputMessage _output(int seq, int size) =>
    OutputMessage(id: 1, seq: seq, data: Uint8List(size));

/// V2-4 E8: the batching rule the desktop's channel and the phone's tool
/// outbox share.
void main() {
  test('measures encoded sizes: three full 16 KiB outputs fit a batch', () {
    final small = [for (var i = 0; i < 50; i++) SessionAttached(id: i)];
    expect(splitIntoBatches(small), hasLength(1));
    final big = [for (var i = 0; i < 7; i++) _output(i, 16 * 1024)];
    final batches = splitIntoBatches(big);
    expect([for (final b in batches) b.length], [3, 3, 1]);
    for (final batch in batches) {
      expect(
        encodeBatch(batch).length,
        lessThanOrEqualTo(kMaxSealedBatchBytes),
      );
    }
  });

  test('full tool chunks go one per batch, in order, small ones with them', () {
    final messages = <AppMessage>[
      for (var i = 0; i < 3; i++)
        ToolData(id: i, data: Uint8List(kToolMaxChunkBytes), end: false),
      const ToolAck([1, 2]),
      const ToolEnd(id: 9, code: 'aborted'),
    ];
    final batches = splitIntoBatches(messages);
    expect([for (final b in batches) b.length], [1, 1, 3]);
    expect([for (final b in batches) ...b], messages);
    for (final batch in batches) {
      expect(
        encodeBatch(batch).length,
        lessThanOrEqualTo(kMaxSealedBatchBytes),
      );
    }
  });
}

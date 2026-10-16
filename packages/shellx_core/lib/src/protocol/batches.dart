import '../channel/secure_channel.dart';
import 'messages.dart';

/// Upper bound for a CBOR array header of up to 65535 items.
const int _arrayHeaderAllowance = 3;

/// Splits [messages], in order, into batches whose encoded CBOR array stays
/// within [kMaxSealedBatchBytes] (so each sealed DATA frame is ≤ 64 KiB).
/// Sizes are measured with [encodeBatch]; three full 16 KiB outputs fit in
/// one batch, four do not. A single message over the limit ends up alone in
/// its batch (sealing it throws: check sizes before queueing). Shared by the
/// desktop's channel and the phone's tool outbox (V2-4 E8).
List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages) {
  final batches = <List<AppMessage>>[];
  var current = <AppMessage>[];
  var size = _arrayHeaderAllowance;
  for (final message in messages) {
    final messageSize = encodeBatch([message]).length - 1;
    if (current.isNotEmpty && size + messageSize > kMaxSealedBatchBytes) {
      batches.add(current);
      current = <AppMessage>[];
      size = _arrayHeaderAllowance;
    }
    current.add(message);
    size += messageSize;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

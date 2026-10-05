import 'dart:math';

/// Session ids start at a random value in [1, 2^31) and then increase by
/// one (spec v1 §6.4), so a phone re-attaching after an agent restart cannot
/// land on a new session that reuses its old id. One allocator is shared by
/// the shell and desktop session managers, so their ids never collide.
int Function() sessionIdAllocator([Random? random]) {
  var next = (random ?? Random.secure()).nextInt((1 << 31) - 1) + 1;
  return () => next++;
}

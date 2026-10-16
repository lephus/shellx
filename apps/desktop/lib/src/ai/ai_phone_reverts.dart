import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// V2-2b B19, R12: a revert a phone made in AI pane [paneId]: [count] files
/// went back.
typedef AiPhoneRevert = ({int paneId, int count});

/// V2-2b B19, R12: the reverts phones make, as they happen. The window's
/// side of AI on phones adds them; each AI pane says its own, at the foot of
/// its Changes panel.
final aiPhoneRevertsProvider = Provider<StreamController<AiPhoneRevert>>((ref) {
  final reverts = StreamController<AiPhoneRevert>.broadcast();
  ref.onDispose(reverts.close);
  return reverts;
});

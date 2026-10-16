import 'package:flutter/widgets.dart';

/// Sent up by a dialog body that has become informational (change
/// password once it says "done"): a scrim click then closes it (UI §4).
final class DialogInformationalNotification extends Notification {
  const DialogInformationalNotification();
}

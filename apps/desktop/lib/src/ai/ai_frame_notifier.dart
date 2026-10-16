import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shellx_ai/shellx_ai.dart';

/// Smoothness: [AiSessionState] calls its listeners on every update, which
/// is hundreds of times a second while an agent streams. Views listen here
/// instead: at most one notification per frame, at the start of that frame
/// (before it builds), never one for nothing.
final class AiFrameNotifier extends ChangeNotifier {
  AiFrameNotifier(this.state) {
    state.addListener(_changed);
  }

  final AiSessionState state;
  var _scheduled = false;
  var _disposed = false;
  var _active = true;
  var _missed = false;

  /// Smoothness: a hidden pane (another tab is selected) hears nothing; it
  /// catches up with one notification when it shows again.
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    if (value && _missed) {
      _missed = false;
      _changed();
    }
  }

  void _changed() {
    if (!_active) {
      _missed = true;
      return;
    }
    if (_scheduled || _disposed) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_changed);
    super.dispose();
  }
}

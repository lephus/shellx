import 'package:flutter/widgets.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../ai/ai_frame_notifier.dart';
import '../../terminal/terminal_tabs.dart';

/// What every part of an AI pane reads: the runtime (its state, and the
/// frame-coalesced notifier views listen to), the tab and pane records, and
/// the pane's own UI state.
class AiPaneScope extends InheritedWidget {
  const AiPaneScope({
    super.key,
    required this.runtime,
    required this.frames,
    required this.tab,
    required this.pane,
    required this.ui,
    required super.child,
  });

  final AiRuntime runtime;
  final AiFrameNotifier frames;
  final TerminalTab tab;
  final AiPaneState pane;
  final AiPaneUi ui;

  AiSessionState get state => runtime.state;

  static AiPaneScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AiPaneScope>();
    assert(scope != null, 'no AiPaneScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AiPaneScope old) =>
      !identical(runtime, old.runtime) ||
      !identical(tab, old.tab) ||
      pane != old.pane;
}

/// The AI pane's own UI state, which its parts change: the overlay over the
/// conversation (run sheet, viewer), the side panel, and text for the
/// composer (Files › "Mention in chat").
final class AiPaneUi extends ChangeNotifier {
  Widget? _overlay;
  var _panel = false;

  Widget? get overlay => _overlay;
  bool get panelOpen => _panel;

  /// Text the composer inserts at its cursor, then clears.
  final insert = ValueNotifier<String?>(null);

  void showOverlay(Widget overlay) {
    _overlay = overlay;
    notifyListeners();
  }

  void closeOverlay() {
    if (_overlay == null) return;
    _overlay = null;
    notifyListeners();
  }

  void togglePanel() {
    _panel = !_panel;
    notifyListeners();
  }

  void openPanel() {
    if (_panel) return;
    _panel = true;
    notifyListeners();
  }

  @override
  void dispose() {
    insert.dispose();
    super.dispose();
  }
}

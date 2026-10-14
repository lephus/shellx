import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
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

/// D8: what a card asks the run sheet to run.
sealed class AiRunRequest {
  const AiRunRequest();
}

/// One of the agent's terminal sign-in methods: its own command plus the
/// method's args and env. Nothing in it is ever read back.
final class AiRunLogin extends AiRunRequest {
  const AiRunLogin(this.method);
  final AuthMethodTerminal method;
}

/// The agent's pinned npm install (D6, D7).
final class AiRunInstall extends AiRunRequest {
  const AiRunInstall();
}

/// The right panel's tabs (§4.4).
enum AiPanelTab { changes, files }

/// The AI pane's own UI state, which its parts change: the overlay over the
/// conversation (run sheet, viewer), the side panel, and text for the
/// composer (Files › "Mention in chat").
final class AiPaneUi extends ChangeNotifier {
  Widget? _overlay;
  var _panel = false;
  var _tab = AiPanelTab.changes;

  Widget? get overlay => _overlay;
  bool get panelOpen => _panel;
  AiPanelTab get panelTab => _tab;

  /// The Changes panel's last result ("Reverted 2 files.", "Wait for the
  /// running turn to finish.").
  final note = ValueNotifier<String?>(null);

  /// Goes up when the project changed under the Changes panel (a revert).
  final changes = ValueNotifier<int>(0);

  /// "Reviewed" marks (`aiReviewKey`), kept while the pane lives.
  final reviewed = <String>{};

  /// Text the composer inserts at its cursor, then clears.
  final insert = ValueNotifier<String?>(null);

  /// Set by the pane: the run sheet (D8).
  void Function(AiRunRequest request)? onRun;

  /// Set by the pane: the folder card (D5, §6 "folder gone").
  void Function()? onChooseFolder;

  /// Set by the pane: "Revert turn" N (§4.4).
  void Function(int turn)? onRevertTurn;

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

  /// Opens the panel on its Changes tab ("View" on a turn summary).
  void openPanel() => showTab(AiPanelTab.changes);

  void showTab(AiPanelTab tab) {
    if (_panel && _tab == tab) return;
    _panel = true;
    _tab = tab;
    notifyListeners();
  }

  void changesChanged() => changes.value++;

  @override
  void dispose() {
    insert.dispose();
    note.dispose();
    changes.dispose();
    super.dispose();
  }
}

/// Smoothness: [builder] runs again only when [select] of the session
/// gives another value (checked once per frame), never per streamed chunk.
class AiSelect<T> extends StatefulWidget {
  const AiSelect({
    super.key,
    required this.frames,
    required this.select,
    required this.builder,
  });

  final AiFrameNotifier frames;
  final T Function(AiSessionState state) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<AiSelect<T>> createState() => _AiSelectState<T>();
}

class _AiSelectState<T> extends State<AiSelect<T>> {
  late T _value = widget.select(widget.frames.state);

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_changed);
  }

  @override
  void didUpdateWidget(AiSelect<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) {
      old.frames.removeListener(_changed);
      widget.frames.addListener(_changed);
    }
    _value = widget.select(widget.frames.state);
  }

  @override
  void dispose() {
    widget.frames.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.select(widget.frames.state);
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

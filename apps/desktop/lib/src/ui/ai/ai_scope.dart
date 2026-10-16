import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Scrollbar;
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

  /// Smoothness: the tab list makes a new record of the tab for anything
  /// that touches it (a focus, a title elsewhere); only another tab (or
  /// runtime, or pane) is worth building every visible item again.
  @override
  bool updateShouldNotify(AiPaneScope old) =>
      !identical(runtime, old.runtime) ||
      tab.id != old.tab.id ||
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

/// D16: the images going with the next message, and what the composer has
/// to say about images ("Claude does not take images.").
final class AiImages extends ChangeNotifier {
  final items = <({Uint8List bytes, String mime})>[];
  String? note;

  void add(Uint8List bytes, String mime) {
    items.add((bytes: bytes, mime: mime));
    note = null;
    notifyListeners();
  }

  void remove(int index) {
    items.removeAt(index);
    notifyListeners();
  }

  void say(String? text) {
    note = text;
    notifyListeners();
  }

  void clear() {
    if (items.isEmpty && note == null) return;
    items.clear();
    note = null;
    notifyListeners();
  }
}

/// Whether the pane [context] is in is on screen. A hidden tab stays in the
/// tree — in an `IndexedStack`, whose children keep their tickers, which is
/// why `TickerMode` alone does not tell — and `Visibility.of` says so; a pane
/// switched off another way stops its tickers (`TickerMode`).
bool aiPaneShown(BuildContext context) =>
    Visibility.of(context) && TickerMode.valuesOf(context).enabled;

/// The AI pane's own UI state, which its parts change: the overlay over the
/// conversation (run sheet, viewer), the side panel, and what goes into the
/// composer (a paste; Files › "Mention in chat").
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

  /// Text the composer inserts at its cursor, then clears: a paste (D16).
  /// Only text — a pasted `@path` is never a file mention.
  final paste = ValueNotifier<String?>(null);

  /// The file the composer mentions next, then clears: [mention].
  final mentioned = ValueNotifier<String?>(null);

  /// Files › "Mention in chat" (D18): the composer puts `@path ` at its
  /// cursor and the file goes along with the message as a `resource_link`
  /// (D16) while its `@path` is still in the text. [path] is relative to the
  /// session folder.
  void mention(String path) => mentioned.value = path;

  /// Set by the pane: the run sheet (D8).
  void Function(AiRunRequest request)? onRun;

  /// Set by the pane: the folder card (D5, §6 "folder gone").
  void Function()? onChooseFolder;

  /// Set by the pane: "Revert turn" N (§4.4).
  void Function(int turn)? onRevertTurn;

  /// Set by the pane: the project's files for `@` (D16), read off the UI
  /// isolate and kept until a turn ends.
  Future<List<String>> Function()? fileIndex;

  /// D16: the images of the next message.
  final images = AiImages();

  /// Set by the pane: the paths of the files copied in Finder / Explorer;
  /// empty: none.
  Future<List<String>> Function()? clipboardFiles;

  /// Set by the pane: an image on the clipboard; null: none.
  Future<Uint8List?> Function()? clipboardImage;

  /// Set by the pane: the bytes of a dropped file, or of a picture file that
  /// was copied (a paste); null: unreadable or over 10 MiB.
  Future<Uint8List?> Function(String path)? readImageFile;

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
    paste.dispose();
    mentioned.dispose();
    note.dispose();
    changes.dispose();
    images.dispose();
    super.dispose();
  }
}

/// Smoothness: [builder] runs again once a second while the pane is on
/// screen — the header's "Running · 0:12", the seconds of a running tool
/// call. A pane that is hidden (another tab is selected) stops its clock, and
/// shows the right time at once when it shows again: nothing ticks that
/// nobody sees.
class AiEverySecond extends StatefulWidget {
  const AiEverySecond({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<AiEverySecond> createState() => _AiEverySecondState();
}

class _AiEverySecondState extends State<AiEverySecond> {
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!aiPaneShown(context)) {
      _stop();
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// [child], at most [max] px high; taller, it scrolls (and says so with a
/// scrollbar). What an agent writes has no length: the dock's buttons and
/// the composer must stay in the window whatever it says.
class AiCapped extends StatefulWidget {
  const AiCapped({super.key, required this.max, required this.child});

  final double max;
  final Widget child;

  @override
  State<AiCapped> createState() => _AiCappedState();
}

class _AiCappedState extends State<AiCapped> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: widget.max),
    child: Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: widget.child,
        ),
      ),
    ),
  );
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

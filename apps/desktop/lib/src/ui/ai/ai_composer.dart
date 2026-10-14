import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// A key the composer offers to others first (the permission bar, D10):
/// [handled] true stops it there.
typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText});

/// What the composer's buttons and hint depend on: rebuilt only when this
/// changes, never per streamed chunk (smoothness: no dropped keystrokes).
typedef _View = ({
  AgentPhase phase,
  bool running,
  bool stopping,
  bool force,
  int? usage,
});

/// The composer (D16, spec §4.1): a field that grows to 140 px and, under
/// it, the context use and Send / Queue / Stop / Force stop.
/// - Enter sends; Shift+Enter is a new line; while the input method is
///   composing (Telex), Enter is the input method's (§1.10).
/// - Sending while a turn runs (or the agent starts) queues (at most 5).
/// - Esc with no question open stops the turn: "Stopping…" at once, "Force
///   stop" after 10 s (§1.4).
class AiComposer extends StatefulWidget {
  const AiComposer({super.key, this.focusNode, this.keyHook});

  /// The window's terminal focus while this pane is the focused one.
  final FocusNode? focusNode;

  /// Keys offered to the permission bar first (Task 16).
  final AiKeyHook? keyHook;

  @override
  State<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends State<AiComposer> {
  final _text = TextEditingController();
  final _ownFocus = FocusNode(debugLabel: 'ai composer');
  AiPaneScope? _scope;
  _View? _view;
  String? _note;

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AiPaneScope.of(context);
    if (!identical(scope.frames, _scope?.frames)) {
      _scope?.frames.removeListener(_onFrame);
      _scope?.ui.insert.removeListener(_onInsert);
      scope.frames.addListener(_onFrame);
      scope.ui.insert.addListener(_onInsert);
    }
    _scope = scope;
    _view = _read(scope.state);
  }

  @override
  void dispose() {
    _scope?.frames.removeListener(_onFrame);
    _scope?.ui.insert.removeListener(_onInsert);
    _text.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  _View _read(AiSessionState s) => (
    phase: s.phase,
    running: s.turn != null,
    stopping: s.turn?.cancelRequested ?? false,
    force: s.turn?.canForceStop ?? false,
    usage: s.usage?.percent,
  );

  void _onFrame() {
    final next = _read(_scope!.state);
    if (next != _view) setState(() => _view = next);
  }

  /// Files › "Mention in chat" (D18): text at the cursor.
  void _onInsert() {
    final insert = _scope!.ui.insert;
    final add = insert.value;
    if (add == null) return;
    insert.value = null;
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, end, add),
      selection: TextSelection.collapsed(offset: at + add.length),
    );
    _focus.requestFocus();
  }

  bool get _canSend => switch (_view!.phase) {
    AgentPhase.needsAuth || AgentPhase.failed => false,
    _ => true,
  };

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty || !_canSend) return;
    final scope = _scope!;
    final l10n = AppLocalizations.of(context);
    _text.clear();
    setState(() => _note = null);
    final ok = await scope.runtime.send([TextBlock(text.trim())]);
    if (ok || !mounted) return;
    _text.text = text;
    setState(
      () => _note = scope.state.queue.length >= AiSessionState.maxQueue
          ? l10n.aiQueueFull
          : l10n.aiCannotSend,
    );
  }

  void _stop() {
    final runtime = _scope!.runtime;
    final turn = runtime.state.turn;
    if (turn == null) return;
    if (turn.canForceStop) {
      unawaited(runtime.forceStop());
    } else {
      runtime.cancel();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // §1.10: the input method's keys while it composes.
    if (_text.value.composing.isValid) return KeyEventResult.ignored;
    if (widget.keyHook?.call(event, hasText: _text.text.isNotEmpty) ?? false) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      unawaited(_send());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _view!.running) {
      _stop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = _scope!;
    final view = _view!;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        ShellxSpace.s16,
        ShellxSpace.s4,
        ShellxSpace.s16,
        ShellxSpace.s12,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.borderInput),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: AiSizes.composerMax),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: Shortcuts(
                shortcuts: textEditingShortcuts(),
                child: TextField(
                  key: const Key('ai.composer'),
                  controller: _text,
                  focusNode: _focus,
                  enabled: _canSend,
                  minLines: 2,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.aiComposerHint(scope.state.agentName),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(ShellxSpace.s12),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s8,
              0,
              ShellxSpace.s8,
              ShellxSpace.s8,
            ),
            child: Row(
              children: [
                if (_note case final note?)
                  Expanded(
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.warn,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (view.usage case final percent?)
                  Padding(
                    padding: const EdgeInsets.only(right: ShellxSpace.s8),
                    child: Text(
                      l10n.aiContextUsed(percent),
                      key: const Key('ai.context'),
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                _SendButton(
                  view: view,
                  hasText: _text,
                  onSend: () => unawaited(_send()),
                  onStop: _stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Send (⏎) / Queue (⏎) / Stop (Esc) / Stopping… / Force stop.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.view,
    required this.hasText,
    required this.onSend,
    required this.onStop,
  });

  final _View view;
  final TextEditingController hasText;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: hasText,
      builder: (context, value, _) {
        final text = value.text.trim().isNotEmpty;
        if (view.running && !text) {
          if (view.force) {
            return FilledButton.icon(
              key: const Key('ai.forceStop'),
              style: destructiveButtonStyle(),
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: Text(l10n.aiForceStop),
            );
          }
          return OutlinedButton.icon(
            key: const Key('ai.stop'),
            onPressed: view.stopping ? null : onStop,
            icon: const Icon(Icons.stop, size: 16),
            label: Text(
              view.stopping ? l10n.aiStopping : '${l10n.aiStop}  Esc',
            ),
          );
        }
        return FilledButton.icon(
          key: const Key('ai.send'),
          onPressed: text ? onSend : null,
          icon: const Icon(Icons.send, size: 16),
          label: Text('${view.running ? l10n.aiQueue : l10n.aiSend}  ⏎'),
        );
      },
    );
  }
}

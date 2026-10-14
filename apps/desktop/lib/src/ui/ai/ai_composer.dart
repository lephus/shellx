import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_completer.dart';
import 'ai_config_chips.dart';
import 'ai_images.dart';
import 'ai_permission_bar.dart' show aiPermissionDigit;
import 'ai_scope.dart';
import 'ai_theme.dart';

/// A key the composer offers to others first (the permission bar, D10):
/// [handled] true stops it there.
typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText});

/// The text field's keys: a paste becomes [AiPasteIntent] (an image first,
/// D16); the rest as in every field of the window.
final Map<ShortcutActivator, Intent> _keys = {
  for (final MapEntry(:key, :value) in textEditingShortcuts().entries)
    key: value is PasteTextIntent ? const AiPasteIntent() : value,
};

/// What the composer's buttons and hint depend on: rebuilt only when this
/// changes, never per streamed chunk (smoothness: no dropped keystrokes).
typedef _View = ({
  AgentPhase phase,
  bool running,
  bool stopping,
  bool force,
  bool queueFull,
  int? usage,
});

/// An image going with a message.
typedef _Image = ({Uint8List bytes, String mime});

/// What the composer says in place of the chips, for as long as it is true.
enum _Note { queueFull, cannotSend }

/// The composer (D16, spec §4.1): a field that grows to 140 px and, under
/// it, the context use and Send / Queue / Stop / Force stop.
/// - Enter sends; Shift+Enter is a new line; while the input method is
///   composing (Telex), Enter is the input method's (§1.10).
/// - Sending while a turn runs (or the agent starts) queues (at most 5).
/// - Esc with no question open stops the turn: "Stopping…" at once, "Force
///   stop" after 10 s (§1.4) — a button; Esc never kills the agent.
class AiComposer extends ConsumerStatefulWidget {
  const AiComposer({super.key, this.focusNode, this.keyHook});

  /// The window's terminal focus while this pane is the focused one.
  final FocusNode? focusNode;

  /// Keys offered to the permission bar first (Task 16).
  final AiKeyHook? keyHook;

  @override
  ConsumerState<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends ConsumerState<AiComposer> {
  final _text = TextEditingController();
  final _ownFocus = FocusNode(debugLabel: 'ai composer');
  AiPaneScope? _scope;
  _View? _view;
  _Note? _note;

  /// D16: `@` file suggestions; the files mentioned so far (sent along as
  /// `resource_link` while their `@path` is still in the text).
  late final _completer = AiCompleter(
    files: () => _scope?.ui.fileIndex?.call() ?? Future.value(const []),
    commands: () => _scope?.state.commands ?? const [],
  );
  final _mentions = <String>{};

  /// The Esc or digit key taken on key-down, until it is let go: its repeats
  /// are taken too (holding Esc after a reject must not also stop the turn;
  /// a held digit must not type).
  LogicalKeyboardKey? _held;

  /// Messages go out in the order they were sent, even when one waits for
  /// its images to be encoded.
  Future<void> _tail = Future.value();

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  void _onText() => unawaited(_completer.update(_text.value));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AiPaneScope.of(context);
    if (!identical(scope.frames, _scope?.frames)) {
      _scope?.frames.removeListener(_onFrame);
      scope.frames.addListener(_onFrame);
    }
    if (!identical(scope.ui, _scope?.ui)) {
      _scope?.ui.paste.removeListener(_onPaste);
      _scope?.ui.mentioned.removeListener(_onMention);
      scope.ui.paste.addListener(_onPaste);
      scope.ui.mentioned.addListener(_onMention);
    }
    _scope = scope;
    _view = _read(scope.state);
    if (!_noteHolds(_view!)) _note = null;
  }

  @override
  void dispose() {
    _scope?.frames.removeListener(_onFrame);
    _scope?.ui.paste.removeListener(_onPaste);
    _scope?.ui.mentioned.removeListener(_onMention);
    _text.dispose();
    _ownFocus.dispose();
    _completer.dispose();
    super.dispose();
  }

  _View _read(AiSessionState s) => (
    phase: s.phase,
    running: s.turn != null,
    stopping: s.turn?.cancelRequested ?? false,
    force: s.turn?.canForceStop ?? false,
    queueFull: s.queue.length >= AiSessionState.maxQueue,
    usage: s.usage?.percent,
  );

  static bool _canSendIn(AgentPhase phase) => switch (phase) {
    AgentPhase.needsAuth || AgentPhase.failed => false,
    _ => true,
  };

  bool get _canSend => _canSendIn(_view!.phase);

  /// A note stays only while it is true.
  bool _noteHolds(_View v) => switch (_note) {
    null => false,
    _Note.queueFull => v.queueFull,
    _Note.cannotSend => !_canSendIn(v.phase),
  };

  void _onFrame() {
    final next = _read(_scope!.state);
    if (next == _view) return;
    setState(() {
      _view = next;
      if (!_noteHolds(next)) _note = null;
    });
  }

  /// [add] goes in at the cursor, over what is selected; the field keeps the
  /// keyboard.
  void _insert(String add) {
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, end, add),
      selection: TextSelection.collapsed(offset: at + add.length),
    );
    _focus.requestFocus();
  }

  /// A paste (D16): text, nothing else — a pasted `@path` is no mention.
  void _onPaste() {
    final paste = _scope!.ui.paste;
    final add = paste.value;
    if (add == null) return;
    paste.value = null;
    _insert(add);
  }

  /// Files › "Mention in chat" (D18): `@path ` at the cursor; the file goes
  /// along as a `resource_link`.
  void _onMention() {
    final mentioned = _scope!.ui.mentioned;
    final path = mentioned.value;
    if (path == null) return;
    mentioned.value = null;
    _insert('@$path ');
    _mentions.add(path);
  }

  /// A suggestion goes in place of what was typed; the field keeps the
  /// keyboard (a click on the list is a click outside the field).
  void _take([int? index]) {
    final (value, pick) = _completer.accept(_text.value, index);
    _text.value = value;
    if (pick.mention case final path?) _mentions.add(path);
    _focus.requestFocus();
  }

  /// The "/" button: a command starts the message.
  void _startCommand() {
    final text = _text.text.startsWith('/') ? _text.text : '/${_text.text}';
    _text.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 1),
    );
    _focus.requestFocus();
  }

  /// The "@" button: a mention starts at the cursor.
  void _startMention() {
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final space = at > 0 && v.text[at - 1].trim().isNotEmpty ? ' ' : '';
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, at, '$space@'),
      selection: TextSelection.collapsed(offset: at + space.length + 1),
    );
    _focus.requestFocus();
  }

  /// Enter, Send, Queue: the message leaves the composer at once; it goes to
  /// the agent after the ones sent before it. A message the agent cannot take
  /// comes back whole: text, images and files.
  Future<void> _send() {
    final scope = _scope!;
    final text = _text.text;
    final images = [...scope.ui.images.items];
    if ((text.trim().isEmpty && images.isEmpty) || !_canSend) {
      return Future.value();
    }
    // D16: each file still mentioned goes along as a `resource_link`.
    final mentions = {
      for (final path in _mentions)
        if (text.contains('@$path')) path,
    };
    final run = ref.read(aiOffThreadProvider);
    _mentions.clear();
    scope.ui.images.clear();
    _text.clear();
    setState(() => _note = null);
    return _tail = _tail.then(
      (_) => _deliver(scope, run, text, images, mentions),
    );
  }

  Future<void> _deliver(
    AiPaneScope scope,
    OffThread run,
    String text,
    List<_Image> images,
    Set<String> mentions,
  ) async {
    final cwd = scope.state.cwd;
    // D16: the images, as `image` blocks (base64 off the UI isolate when big).
    final data = await aiEncodeImages(run, [for (final i in images) i.bytes]);
    final blocks = <ContentBlock>[
      if (text.trim().isNotEmpty) TextBlock(text.trim()),
      for (final (i, image) in images.indexed)
        ImageBlock(data: data[i], mimeType: image.mime),
      for (final path in mentions)
        ResourceLinkBlock(
          uri: Uri.file(p.join(cwd, path)).toString(),
          name: p.basename(path),
          title: path,
        ),
    ];
    final ok = await scope.runtime.send(blocks);
    if (ok || !mounted) return;
    // Nothing is lost: the text (before what was typed meanwhile), the
    // images and the files come back.
    _mentions.addAll(mentions);
    for (final image in images) {
      scope.ui.images.add(image.bytes, image.mime);
    }
    final now = _text.text;
    final all = now.isEmpty ? text : '$text\n$now';
    _text.value = TextEditingValue(
      text: all,
      selection: TextSelection.collapsed(offset: all.length),
    );
    setState(
      () => _note = scope.state.queue.length >= AiSessionState.maxQueue
          ? _Note.queueFull
          : _Note.cannotSend,
    );
  }

  /// Stop (Esc): the turn is asked to end. Never more than that.
  void _cancel() => _scope!.runtime.cancel();

  /// "Force stop": the button, after the turn did not end in time.
  void _forceStop() => unawaited(_scope!.runtime.forceStop());

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == _held) _held = null;
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent && key == _held) return KeyEventResult.handled;
    if (event is KeyDownEvent) _held = null;
    final result = _handle(event);
    if (result == KeyEventResult.handled &&
        event is KeyDownEvent &&
        (key == LogicalKeyboardKey.escape || aiPermissionDigit(key) != null)) {
      _held = key;
    }
    return result;
  }

  KeyEventResult _handle(KeyEvent event) {
    // §1.10: the input method's keys while it composes.
    if (_text.value.composing.isValid) return KeyEventResult.ignored;
    // D16: an open suggestion list takes its keys first (Esc closes it,
    // never a question).
    if (_completer.active) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
          _completer.move(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _completer.move(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter ||
            LogicalKeyboardKey.numpadEnter ||
            LogicalKeyboardKey.tab:
          _take();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _completer.dismiss();
          return KeyEventResult.handled;
      }
    }
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
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = _scope!;
    final view = _view!;
    final note = switch (_note) {
      _Note.queueFull => l10n.aiQueueFull,
      _Note.cannotSend => l10n.aiCannotSend,
      null => null,
    };
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
          ListenableBuilder(
            listenable: _completer,
            builder: (context, _) => _completer.active
                ? _Suggestions(completer: _completer, onPick: _take)
                : const SizedBox.shrink(),
          ),
          AiAttachments(focus: _focus),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: AiSizes.composerMax),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: Shortcuts(
                shortcuts: _keys,
                child: TextField(
                  key: const Key('ai.composer'),
                  controller: _text,
                  focusNode: _focus,
                  // Never `enabled: false`: a disabled field gives up the
                  // keyboard, and it would not come back once the agent is
                  // ready (signed in, restarted).
                  readOnly: !_canSend,
                  minLines: 2,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    // A failed agent is not "coming": say what is so.
                    hintText: switch (view.phase) {
                      AgentPhase.failed => l10n.aiCannotSend,
                      AgentPhase.needsAuth => l10n.aiComposerWaiting,
                      _ => l10n.aiComposerHint(scope.state.agentName),
                    },
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
                IconButton(
                  key: const Key('ai.mention'),
                  tooltip: l10n.aiMention,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: _canSend ? _startMention : null,
                  icon: const Icon(Icons.alternate_email),
                ),
                IconButton(
                  key: const Key('ai.commands'),
                  tooltip: l10n.aiCommands,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: _canSend ? _startCommand : null,
                  icon: const Icon(Icons.terminal),
                ),
                if (note != null)
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
                  // D11: mode, model, thinking.
                  const Expanded(child: AiConfigChips()),
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
                  text: _text,
                  images: scope.ui.images,
                  onSend: () => unawaited(_send()),
                  onCancel: _cancel,
                  onForce: _forceStop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// D16: the suggestions over the field: the selected one lit; a click
/// takes one.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.completer, required this.onPick});

  final AiCompleter completer;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.all(ShellxSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in completer.items.indexed)
            InkWell(
              key: Key('ai.suggest.$i'),
              onTap: () => onPick(i),
              child: Container(
                color: i == completer.selected
                    ? ShellxDesktopColors.rowSelected
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: ShellxSpace.s8,
                  vertical: ShellxSpace.s2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kAiMono,
                      ),
                    ),
                    if (s.detail case final detail?)
                      Flexible(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Send (⏎) / Queue (⏎) / Stop (Esc) / Stopping… / Force stop. A message is
/// text or an image; while a turn runs, or the agent starts, it queues.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.view,
    required this.text,
    required this.images,
    required this.onSend,
    required this.onCancel,
    required this.onForce,
  });

  final _View view;
  final TextEditingController text;
  final AiImages images;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onForce;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: text,
      builder: (context, value, _) => ListenableBuilder(
        listenable: images,
        builder: (context, _) {
          final content =
              value.text.trim().isNotEmpty || images.items.isNotEmpty;
          // The turn did not end in time: the way out stays, whatever is
          // typed.
          if (view.force) {
            return FilledButton.icon(
              key: const Key('ai.forceStop'),
              style: destructiveButtonStyle(),
              onPressed: onForce,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: Text(l10n.aiForceStop),
            );
          }
          if (view.running && (view.stopping || !content)) {
            return OutlinedButton.icon(
              key: const Key('ai.stop'),
              onPressed: view.stopping ? null : onCancel,
              icon: const Icon(Icons.stop, size: 16),
              label: Text(
                view.stopping ? l10n.aiStopping : '${l10n.aiStop}  Esc',
              ),
            );
          }
          // The prompt waits when a turn runs and while the agent starts.
          final queues = view.running || view.phase == AgentPhase.starting;
          return FilledButton.icon(
            key: const Key('ai.send'),
            onPressed: content ? onSend : null,
            icon: const Icon(Icons.send, size: 16),
            label: Text('${queues ? l10n.aiQueue : l10n.aiSend}  ⏎'),
          );
        },
      ),
    );
  }
}

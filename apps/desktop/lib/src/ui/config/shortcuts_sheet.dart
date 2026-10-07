import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../../config/config_syntax.dart' show decodeConfigBytes;
import '../../config/config_template.dart';
import '../../config/config_writer.dart';
import '../../config/keybind_actions.dart';
import '../../config/keybind_trigger.dart';
import '../../config/keybindings.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'action_labels.dart';
import 'command_palette.dart' show Keycaps, matchScore;

/// How long a D25 note stays under its row.
const Duration kShortcutNoteVisible = Duration(seconds: 4);

/// UI-A9 §4: every action, its chords, add / remove / reset. The only
/// writes are the user's own clicks and keys here (never on load), and
/// they touch the managed block of the ShellX file only (D32).
class ShortcutsSheet extends ConsumerStatefulWidget {
  const ShortcutsSheet({
    super.key,
    required this.onClose,
    required this.onOpenFile,
  });
  final VoidCallback onClose;
  final VoidCallback onOpenFile;

  @override
  ConsumerState<ShortcutsSheet> createState() => _ShortcutsSheetState();
}

class _ShortcutsSheetState extends ConsumerState<ShortcutsSheet> {
  final _search = TextEditingController();
  final _recorder = FocusNode(debugLabel: 'shortcut recorder');
  final _addFocus = FocusNode(debugLabel: 'shortcut add');
  String _query = '';
  KeyAction? _recording;

  /// The row whose "Add shortcut" gets the keyboard back after recording.
  KeyAction? _lastRecorded;
  String? _error;
  ({KeyChord chord, KeyAction other})? _conflict;

  /// The modifiers held while recording ("⌘⇧…").
  String _held = '';

  /// A D25 note of the chord just recorded, 4 s under its row.
  ({KeyAction action, String text})? _note;
  Timer? _noteTimer;

  /// The marker lines of the managed block in the ShellX file as last
  /// read; a chord set on a line inside it is the app's own (D19).
  ({int first, int last})? _managed;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readManaged());
    ref.listenManual(
      shellxConfigProvider.select((s) => s.generation),
      (_, _) => unawaited(_readManaged()),
    );
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    _search.dispose();
    _recorder.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  bool get _mac => ref.read(configPlatformProvider) == TargetPlatform.macOS;

  Future<void> _readManaged() async {
    ({int first, int last})? range;
    try {
      final bytes = await ref
          .read(configFileStoreProvider)
          .read(ref.read(configPathsProvider).shellx);
      if (bytes != null) range = managedLineRange(decodeConfigBytes(bytes));
    } catch (_) {
      // Unreadable: every file chord shows as written by hand.
    }
    if (mounted && range != _managed) setState(() => _managed = range);
  }

  List<(ActionGroup, KeyAction)> _rows(ConfigState s) {
    final names = <String>{};
    return [
      for (final spec in kActionSpecs.values)
        if (!const {
          'text',
          'csi',
          'esc',
          'ignore',
          'run_command',
        }.contains(spec.name))
          for (final param in actionVariants(spec))
            (spec.group, KeyAction(spec.name, param)),
      for (final c in s.config.commands)
        if (names.add(c.name))
          (ActionGroup.commands, KeyAction('run_command', c.name)),
    ];
  }

  void _announce(String message) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    ),
  );

  void _startRecording(KeyAction action) {
    setState(() {
      _recording = action;
      _lastRecorded = action;
      _error = null;
      _conflict = null;
      _held = '';
    });
    // The recorder's Focus is built in this frame; focus it after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recorder.requestFocus();
    });
  }

  /// Leaves recording; the keyboard goes back to the row's "Add shortcut"
  /// unless it is moving on by itself (Tab).
  void _stopRecording({bool restoreFocus = true}) {
    setState(() {
      _recording = null;
      _error = null;
      _conflict = null;
      _held = '';
    });
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _addFocus.context != null) _addFocus.requestFocus();
      });
    }
  }

  /// "⌘⇧" / "Ctrl+Shift": what is held, in [chordLabel]'s order.
  String _heldLabel() {
    final k = HardwareKeyboard.instance;
    if (_mac) {
      return '${k.isMetaPressed ? '⌘' : ''}${k.isControlPressed ? '⌃' : ''}'
          '${k.isAltPressed ? '⌥' : ''}${k.isShiftPressed ? '⇧' : ''}';
    }
    return [
      if (k.isControlPressed) 'Ctrl',
      if (k.isShiftPressed) 'Shift',
      if (k.isAltPressed) 'Alt',
      if (k.isMetaPressed) 'Win',
    ].join('+');
  }

  KeyEventResult _onRecordKey(FocusNode node, KeyEvent event) {
    final action = _recording;
    if (action == null) return KeyEventResult.ignored;
    final chord = chordOfEvent(event, HardwareKeyboard.instance);
    if (chord == null) {
      // A modifier on its own: shown while held, never recorded.
      final held = _heldLabel();
      if (held != _held) setState(() => _held = held);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final plain = !chord.hasCommandModifier;
    if (plain && !chord.shift && chord.key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return KeyEventResult.handled;
    }
    if (plain && chord.key == LogicalKeyboardKey.tab) {
      _stopRecording(restoreFocus: false);
      return KeyEventResult.ignored; // the focus moves on (WCAG 2.1.2)
    }
    unawaited(_accept(action, chord));
    return KeyEventResult.handled;
  }

  void _refuse(AppLocalizations l10n, String text) {
    setState(() {
      _error = text;
      _held = '';
    });
    _announce(text);
  }

  Future<void> _accept(KeyAction action, KeyChord chord) async {
    final l10n = AppLocalizations.of(context);
    final state = ref.read(shellxConfigProvider);
    final platform = ref.read(configPlatformProvider);
    final label = chordLabel(chord, mac: _mac);
    ConfigProblem problem(ConfigProblemCode code) => ConfigProblem(
      file: '',
      line: 0,
      severity: ConfigSeverity.error,
      code: code,
      value: label,
    );
    // D26: with AltGr held the key is the layout's, no window shortcut
    // runs for it; recording it would bind a chord that never fires.
    if (altGrHeld(HardwareKeyboard.instance.logicalKeysPressed, platform)) {
      return _refuse(
        l10n,
        problemText(l10n, problem(ConfigProblemCode.altGrTrigger)),
      );
    }
    final rule = checkTrigger(
      [chord],
      action,
      mac: _mac,
      optionAsAlt: state.config.optionAsAlt,
    );
    if (rule.error != null || chordConfigText(chord) == null) {
      return _refuse(
        l10n,
        problemText(l10n, problem(rule.error ?? ConfigProblemCode.badTrigger)),
      );
    }
    final scope = kActionSpecs[action.name]!.scope;
    final existing = state.bindings.find([chord], scope);
    if (existing != null && existing.action == action) {
      _stopRecording();
      return;
    }
    if (existing != null) {
      setState(() {
        _conflict = (chord: chord, other: existing.action);
        _held = '';
      });
      _announce(
        l10n.shortcutsConflict(label, actionLabel(l10n, existing.action)),
      );
      return;
    }
    await _write(
      [AddBinding(chord, action)],
      l10n.shortcutsAssigned(label, actionLabel(l10n, action)),
      note: rule.notes.isEmpty
          ? null
          : (
              action: action,
              text: problemText(l10n, problem(rule.notes.first)),
            ),
    );
  }

  Future<void> _write(
    List<BindingEdit> edits,
    String announcement, {
    ({KeyAction action, String text})? note,
  }) async {
    if (_writing) return;
    _writing = true;
    final paths = ref.read(configPathsProvider);
    final template = shellxTemplate(ref.read);
    try {
      await ref
          .read(configFileWriterProvider)
          .edit(paths.shellx, edits, template: template);
    } catch (error) {
      // Never the text or the path in the log: only what went wrong.
      debugPrint('ShellX: shortcut not saved: ${error.runtimeType}');
      _writing = false;
      ref
          .read(terminalTabsProvider.notifier)
          .showNotice(ConfigWriteFailedNotice(paths.shellx));
      // A file that changed under us: show what is on disk now.
      if (error is ConfigWriteRefused) {
        unawaited(ref.read(shellxConfigProvider.notifier).load());
      }
      if (mounted && _recording != null) _stopRecording();
      return;
    }
    _writing = false;
    if (!mounted) return;
    _showNote(note);
    _stopRecording();
    await ref.read(shellxConfigProvider.notifier).load();
    if (mounted) _announce(announcement);
  }

  void _showNote(({KeyAction action, String text})? note) {
    _noteTimer?.cancel();
    setState(() => _note = note);
    if (note == null) return;
    _noteTimer = Timer(kShortcutNoteVisible, () {
      if (mounted) setState(() => _note = null);
    });
    _announce(note.text);
  }

  bool _isDefault(KeyChord chord) => defaultKeyBindings(
    ref.read(configPlatformProvider),
  ).any((b) => b.sequence.length == 1 && b.sequence.single == chord);

  /// D19: a chord from a line of the ShellX file outside the managed block.
  bool _writtenByHand(KeyBinding b, String shellx) {
    final origin = b.origin;
    if (origin == null) return false;
    if (origin.file != shellx) return true;
    final m = _managed;
    return m == null || origin.line < m.first || origin.line > m.last;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shellxConfigProvider);
    final size = MediaQuery.sizeOf(context);
    final rows = [
      for (final (group, action) in _rows(state))
        if (_query.isEmpty ||
            matchScore(_query, actionLabel(l10n, action)) != null)
          (group, action),
    ];
    final shellx = ref.read(configPathsProvider).shellx;
    ActionGroup? lastGroup;
    final children = <Widget>[];
    for (final (group, action) in rows) {
      if (group != lastGroup) {
        lastGroup = group;
        children.add(
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.shortcutsGroup(group.name).toUpperCase(),
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }
      children.add(_row(l10n, state, action, shellx));
    }
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.shortcutsTitle,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_recording == null) widget.onClose();
          },
        },
        child: FocusScope(
          autofocus: true,
          child: Container(
            width: math.min(ShellxSizes.shortcutsWidth, size.width - 48),
            height: math.min(ShellxSizes.shortcutsHeight, size.height - 64),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.surface,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.border),
              boxShadow: ShellxShadows.e1,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.shortcutsTitle,
                            style: ShellxText.bodyStrong.copyWith(
                              color: ShellxDesktopColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Semantics(
                      textField: true,
                      label: l10n.shortcutsSearchLabel,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: l10n.shortcutsSearchLabel,
                          prefixIcon: const Icon(Icons.search, size: 16),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: ListView(children: children)),
                  const Divider(height: 1, color: ShellxDesktopColors.line),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.shortcutsFooter,
                            style: ShellxText.small.copyWith(
                              color: ShellxDesktopColors.textSecondary,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: widget.onOpenFile,
                          child: Text(l10n.configOpenFile),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recorderBox(AppLocalizations l10n) {
    final text = _held.isEmpty
        ? l10n.shortcutsRecording
        : l10n.shortcutsHeld(_held);
    return Focus(
      focusNode: _recorder,
      onKeyEvent: _onRecordKey,
      child: Semantics(
        liveRegion: true,
        label: text,
        excludeSemantics: true,
        child: Container(
          height: ShellxSizes.keycapHeight + 8,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surfaceInset,
            borderRadius: BorderRadius.circular(ShellxRadius.r4),
            border: Border.all(
              color: _error == null
                  ? ShellxDesktopColors.accent
                  : ShellxDesktopColors.err,
            ),
          ),
          child: Text(
            text,
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    AppLocalizations l10n,
    ConfigState state,
    KeyAction action,
    String shellx,
  ) {
    final name = actionLabel(l10n, action);
    final bindings = [
      for (final b in state.bindings.all)
        if (b.action == action && b.sequence.length == 1) b,
    ];
    final defaults = defaultChordsOf(action, state.bindings.platform);
    final changed = !listEquals([
      for (final b in bindings) b.sequence.single,
    ], defaults);
    final recording = _recording == action;
    final labels = [
      for (final b in bindings) chordLabel(b.sequence.single, mac: _mac),
    ];
    final note = _note?.action == action ? _note!.text : null;
    return Semantics(
      key: ValueKey('shortcuts.row.${action.text}'),
      container: true,
      label: labels.isEmpty ? name : '$name, ${labels.join(', ')}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: ShellxSizes.shortcutsRow,
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: Tooltip(
                      message: name,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: recording
                        ? _recorderBox(l10n)
                        : Wrap(
                            spacing: ShellxSizes.keycapGap,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (bindings.isEmpty)
                                Text(
                                  l10n.shortcutsNone,
                                  style: ShellxText.small.copyWith(
                                    color: ShellxDesktopColors.textSecondary,
                                  ),
                                ),
                              for (final b in bindings)
                                _chordChip(l10n, b, shellx),
                            ],
                          ),
                  ),
                  if (recording)
                    TextButton(
                      onPressed: _stopRecording,
                      child: Text(l10n.shortcutsCancel),
                    )
                  else ...[
                    Semantics(
                      label: l10n.shortcutsAddFor(name),
                      button: true,
                      excludeSemantics: true,
                      child: TextButton(
                        focusNode: _lastRecorded == action ? _addFocus : null,
                        onPressed: () => _startRecording(action),
                        child: Text(l10n.shortcutsAdd),
                      ),
                    ),
                    if (changed)
                      Semantics(
                        label: l10n.shortcutsResetFor(name),
                        button: true,
                        excludeSemantics: true,
                        child: TextButton(
                          onPressed: () => unawaited(
                            _write([
                              ResetAction(action, defaults),
                            ], l10n.shortcutsResetDone(name)),
                          ),
                          child: Text(l10n.shortcutsReset),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (recording && _error != null)
              Text(
                _error!,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            if (note != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  note,
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
              ),
            if (recording && _conflict != null)
              _conflictBar(l10n, action, name),
          ],
        ),
      ),
    );
  }

  Widget _chordChip(AppLocalizations l10n, KeyBinding b, String shellx) {
    final chord = b.sequence.single;
    final label = chordLabel(chord, mac: _mac);
    final byHand = _writtenByHand(b, shellx);
    final keycaps = Keycaps(label: label, dashed: byHand);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (byHand && b.origin!.file == shellx)
          Tooltip(
            message: l10n.shortcutsFromFile(b.origin!.line),
            child: keycaps,
          )
        else
          keycaps,
        Semantics(
          button: true,
          label: l10n.shortcutsRemove(label),
          excludeSemantics: true,
          child: InkResponse(
            radius: 10,
            onTap: () => unawaited(
              _write([
                RemoveBinding(chord, isDefault: _isDefault(chord)),
              ], l10n.shortcutsRemoved(label)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 12,
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _conflictBar(AppLocalizations l10n, KeyAction action, String name) {
    final conflict = _conflict!;
    final label = chordLabel(conflict.chord, mac: _mac);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.warnBg,
        border: Border.all(color: ShellxDesktopColors.warnBorder),
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.shortcutsConflict(
                  label,
                  actionLabel(l10n, conflict.other),
                ),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: _stopRecording,
            child: Text(l10n.shortcutsCancel),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => unawaited(
              _write([
                AddBinding(conflict.chord, action),
              ], l10n.shortcutsAssigned(label, name)),
            ),
            child: Text(l10n.shortcutsReplace),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart';
import '../../config/config_problem.dart';
import '../../config/keybind_trigger.dart';
import '../config/action_labels.dart' show problemText;
import '../theme/shellx_desktop_theme.dart';

/// A11 D22: the control of the `global-hotkey` row: a button that shows the
/// chord (or "Not set"), records the next key combination, and hands its
/// config spelling to the row to write. Esc cancels, a modifier alone is
/// shown while held and never recorded, Tab moves on. What is acceptable is
/// the loader's call (the row shows its words), not this widget's.
class HotkeyControl extends ConsumerStatefulWidget {
  const HotkeyControl({
    super.key,
    required this.label,
    required this.current,
    required this.editable,
    required this.onCommit,
  });

  /// The row's label (the button's accessible name).
  final String label;

  /// The chord in effect as config text; empty when off.
  final String current;
  final bool editable;
  final Future<void> Function(String raw) onCommit;

  @override
  ConsumerState<HotkeyControl> createState() => _HotkeyControlState();
}

class _HotkeyControlState extends ConsumerState<HotkeyControl> {
  final _recorder = FocusNode(debugLabel: 'hotkey recorder');
  final _button = FocusNode(debugLabel: 'hotkey button');
  bool _recording = false;
  String _held = '';
  String? _error;

  @override
  void dispose() {
    _recorder.dispose();
    _button.dispose();
    super.dispose();
  }

  bool get _mac => ref.read(configPlatformProvider) == TargetPlatform.macOS;

  void _start() {
    setState(() {
      _recording = true;
      _held = '';
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recorder.requestFocus();
    });
  }

  void _stop({bool restoreFocus = true}) {
    setState(() {
      _recording = false;
      _held = '';
    });
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _button.context != null) _button.requestFocus();
      });
    }
  }

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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;
    final chord = chordOfEvent(event, HardwareKeyboard.instance);
    if (chord == null) {
      final held = _heldLabel();
      if (held != _held) setState(() => _held = held);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final plain = !chord.hasCommandModifier;
    if (plain && !chord.shift && chord.key == LogicalKeyboardKey.escape) {
      _stop();
      return KeyEventResult.handled;
    }
    if (plain && chord.key == LogicalKeyboardKey.tab) {
      _stop(restoreFocus: false);
      return KeyEventResult.ignored; // the focus moves on (WCAG 2.1.2)
    }
    final l10n = AppLocalizations.of(context);
    ConfigProblem problem(ConfigProblemCode code) => ConfigProblem(
      file: '',
      line: 0,
      severity: ConfigSeverity.error,
      code: code,
    );
    // The key is the layout's with AltGr held: no global shortcut for it.
    if (altGrHeld(
      HardwareKeyboard.instance.logicalKeysPressed,
      ref.read(configPlatformProvider),
    )) {
      _refuse(problemText(l10n, problem(ConfigProblemCode.altGrTrigger)));
      return KeyEventResult.handled;
    }
    final text = chordConfigText(chord);
    if (text == null) {
      _refuse(problemText(l10n, problem(ConfigProblemCode.badTrigger)));
      return KeyEventResult.handled;
    }
    _stop();
    unawaited(widget.onCommit(text));
    return KeyEventResult.handled;
  }

  void _refuse(String text) {
    setState(() {
      _error = text;
      _held = '';
    });
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chord = parseKeyChord(widget.current);
    final shown = chord == null
        ? l10n.settingsGlobalHotkeyNone
        : chordLabel(chord, mac: _mac);
    // A refused registration (another app has the key).
    final taken =
        chord != null &&
        ref.watch(
          shellxConfigProvider.select(
            (s) => s.runtimeProblems.any((p) => p.key == 'global-hotkey'),
          ),
        );
    final recordingText = _held.isEmpty
        ? l10n.settingsGlobalHotkeyRecord
        : l10n.shortcutsHeld(_held);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recording)
          Focus(
            focusNode: _recorder,
            onKeyEvent: _onKey,
            child: Semantics(
              liveRegion: true,
              label: recordingText,
              excludeSemantics: true,
              child: Container(
                key: const Key('setting.global-hotkey.recording'),
                height: ShellxSizes.keycapHeight + 8,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: ShellxDesktopColors.surfaceInset,
                  borderRadius: BorderRadius.circular(ShellxRadius.r4),
                  border: Border.all(color: ShellxDesktopColors.accent),
                ),
                child: Text(
                  recordingText,
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
            ),
          )
        else
          Semantics(
            button: true,
            label: '${widget.label}: $shown',
            excludeSemantics: true,
            child: OutlinedButton(
              key: const Key('setting.global-hotkey.record'),
              focusNode: _button,
              onPressed: widget.editable ? _start : null,
              child: Text(shown),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.settingsGlobalHotkeyUndetected,
            key: const Key('setting.global-hotkey.hint'),
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          ),
        if (taken)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.settingsGlobalHotkeyTaken,
                key: const Key('setting.global-hotkey.taken'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.warn,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

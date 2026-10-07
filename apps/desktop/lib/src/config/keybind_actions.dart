import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../terminal/edit_line.dart';
import '../terminal/pane_layout.dart';
import '../ui/terminal/terminal_intents.dart';
import 'config_problem.dart';
import 'config_syntax.dart';

/// D27's fixed scopes. A6 (browser panes) is not merged: no action has the
/// browser scope yet ("browser pending A6").
enum KeyScope { window, browser }

/// UI-A9 §4.1 groups, in display order.
enum ActionGroup {
  tabs,
  panes,
  notifications,
  editing,
  font,
  browser,
  window,
  config,
  commands,
}

/// `name` or `name:param` (D23).
@immutable
final class KeyAction {
  const KeyAction(this.name, [this.param]);
  final String name;
  final String? param;

  String get text => param == null ? name : '$name:$param';

  @override
  bool operator ==(Object other) =>
      other is KeyAction && other.name == name && other.param == param;

  @override
  int get hashCode => Object.hash(name, param);

  @override
  String toString() => text;
}

/// [param] normalises a parameter (null = invalid); it receives null when
/// the action is written without ':'. A spec with no [param] takes none.
final class ActionSpec {
  const ActionSpec(
    this.name,
    this.group, {
    this.scope = KeyScope.window,
    this.repeats = false,
    this.param,
    this.paramHint,
    this.inPalette = true,
  });

  final String name;
  final ActionGroup group;
  final KeyScope scope;
  final bool repeats;
  final String? Function(String? raw)? param;
  final String? paramHint;
  final bool inPalette;
}

String? _oneOf(Set<String> allowed, String? raw) =>
    raw != null && allowed.contains(raw.trim()) ? raw.trim() : null;

String? _direction(String? raw) {
  if (raw == null || raw.contains(',')) return null;
  return _side(raw);
}

/// `resize_split` alone accepts (and ignores, with a note) `,N`.
String? _resizeDirection(String? raw) =>
    raw == null ? null : _side(raw.split(',').first);

String? _side(String raw) {
  final first = raw.trim();
  return switch (first) {
    'left' || 'right' || 'up' || 'down' => first,
    'top' => 'up',
    'bottom' => 'down',
    _ => null,
  };
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

String? _fontStep(String? raw) {
  if (raw == null) return '1';
  final v = double.tryParse(raw.trim());
  if (v == null || v < 0.5 || v > 8) return null;
  return _num(v);
}

String? _editLine(String? raw) =>
    EditLineOp.fromWire(raw?.trim()) == null ? null : raw!.trim();

String? _tabNumber(String? raw) {
  final n = int.tryParse(raw?.trim() ?? '');
  return n != null && n >= 1 && n <= 9 ? '$n' : null;
}

String? _name(String? raw) =>
    raw == null || raw.trim().isEmpty ? null : raw.trim();

/// The text a `text:`/`csi:`/`esc:` binding sends, prefix included, is at
/// most 4096 UTF-8 bytes.
String? Function(String?) _escaped(String prefix) => (raw) {
  if (raw == null || raw.isEmpty) return null;
  final decoded = decodeZigString(raw);
  if (decoded == null) return null;
  return utf8.encode('$prefix$decoded').length > 4096 ? null : raw;
};

const _textHint = r'a Zig string, e.g. text:ls\n';

final Map<String, ActionSpec> kActionSpecs = {
  for (final s in <ActionSpec>[
    const ActionSpec('new_tab', ActionGroup.tabs),
    const ActionSpec('close_surface', ActionGroup.tabs),
    const ActionSpec('close_tab', ActionGroup.tabs),
    // A11 D14: the newest closed tab or pane, with its scrollback.
    const ActionSpec('reopen_closed', ActionGroup.tabs),
    const ActionSpec('new_workspace', ActionGroup.tabs),
    const ActionSpec('ssh_connect', ActionGroup.tabs),
    const ActionSpec('tmux_attach', ActionGroup.tabs),
    const ActionSpec(
      'goto_tab',
      ActionGroup.tabs,
      repeats: true,
      param: _tabNumber,
      paramHint: '1–9',
      inPalette: false,
    ),
    const ActionSpec('next_tab', ActionGroup.tabs, repeats: true),
    const ActionSpec('previous_tab', ActionGroup.tabs, repeats: true),
    ActionSpec(
      'new_split',
      ActionGroup.panes,
      param: (r) => _oneOf({'right', 'down'}, r),
      paramHint: 'right, down',
    ),
    const ActionSpec(
      'goto_split',
      ActionGroup.panes,
      repeats: true,
      param: _direction,
      paramHint: 'left, right, up, down',
    ),
    const ActionSpec(
      'resize_split',
      ActionGroup.panes,
      repeats: true,
      param: _resizeDirection,
      paramHint: 'left, right, up, down',
    ),
    const ActionSpec('toggle_split_zoom', ActionGroup.panes),
    const ActionSpec('equalize_splits', ActionGroup.panes),
    const ActionSpec('toggle_notifications', ActionGroup.notifications),
    const ActionSpec('jump_to_unread', ActionGroup.notifications),
    const ActionSpec('copy_to_clipboard', ActionGroup.editing, repeats: true),
    const ActionSpec(
      'paste_from_clipboard',
      ActionGroup.editing,
      repeats: true,
    ),
    const ActionSpec('select_all', ActionGroup.editing, repeats: true),
    // A10 D4: Ghostty's names.
    const ActionSpec('start_search', ActionGroup.editing),
    ActionSpec(
      'navigate_search',
      ActionGroup.editing,
      repeats: true,
      param: (r) => _oneOf({'next', 'previous'}, r),
      paramHint: 'next, previous',
    ),
    const ActionSpec('end_search', ActionGroup.editing),
    // A11 D11: macOS line editing at the prompt.
    ActionSpec(
      'edit_line',
      ActionGroup.editing,
      repeats: true,
      param: _editLine,
      paramHint:
          'line_start, line_end, delete_line, delete_word, delete_word_forward',
    ),
    // A11 D13: vim-style keys over the buffer, no mouse.
    const ActionSpec('toggle_copy_mode', ActionGroup.editing),
    const ActionSpec(
      'increase_font_size',
      ActionGroup.font,
      repeats: true,
      param: _fontStep,
      paramHint: '0.5–8',
    ),
    const ActionSpec(
      'decrease_font_size',
      ActionGroup.font,
      repeats: true,
      param: _fontStep,
      paramHint: '0.5–8',
    ),
    const ActionSpec('reset_font_size', ActionGroup.font, repeats: true),
    const ActionSpec('next_region', ActionGroup.window, repeats: true),
    const ActionSpec('previous_region', ActionGroup.window, repeats: true),
    const ActionSpec(
      'toggle_command_palette',
      ActionGroup.window,
      inPalette: false,
    ),
    const ActionSpec('reload_config', ActionGroup.config),
    const ActionSpec('open_config', ActionGroup.config),
    const ActionSpec('show_shortcuts', ActionGroup.config),
    const ActionSpec('show_config_problems', ActionGroup.config),
    const ActionSpec(
      'run_command',
      ActionGroup.commands,
      param: _name,
      paramHint: 'a command name',
      inPalette: false,
    ),
    ActionSpec(
      'text',
      ActionGroup.commands,
      repeats: true,
      param: _escaped(''),
      paramHint: _textHint,
      inPalette: false,
    ),
    ActionSpec(
      'csi',
      ActionGroup.commands,
      repeats: true,
      param: _escaped('\x1b['),
      paramHint: _textHint,
      inPalette: false,
    ),
    ActionSpec(
      'esc',
      ActionGroup.commands,
      repeats: true,
      param: _escaped('\x1b'),
      paramHint: _textHint,
      inPalette: false,
    ),
    const ActionSpec(
      'ignore',
      ActionGroup.commands,
      repeats: true,
      inPalette: false,
    ),
  ])
    s.name: s,
};

/// D23. Exactly one of `action` / `problem` is set.
({KeyAction? action, ConfigProblemCode? problem, String? hint}) parseKeyAction(
  String text,
) {
  final colon = text.indexOf(':');
  final name = (colon < 0 ? text : text.substring(0, colon)).trim();
  final raw = colon < 0 ? null : text.substring(colon + 1);
  final spec = kActionSpecs[name];
  if (spec == null) {
    return (action: null, problem: ConfigProblemCode.unknownAction, hint: null);
  }
  final check = spec.param;
  if (check == null) {
    return raw == null
        ? (action: KeyAction(name), problem: null, hint: null)
        : (
            action: null,
            problem: ConfigProblemCode.badActionParam,
            hint: 'no parameter',
          );
  }
  final param = check(raw);
  if (param == null) {
    return (
      action: null,
      problem: ConfigProblemCode.badActionParam,
      hint: spec.paramHint,
    );
  }
  return (action: KeyAction(name, param), problem: null, hint: null);
}

PaneDirection _dir(String p) => PaneDirection.values.byName(p);

/// The window intent an action stands for.
Intent intentForAction(KeyAction a) => switch (a.name) {
  'new_tab' => const NewTabIntent(),
  'close_surface' => const CloseTabIntent(),
  'close_tab' => const CloseWholeTabIntent(),
  'reopen_closed' => const ReopenClosedIntent(),
  'new_workspace' => const NewWorkspaceIntent(),
  'ssh_connect' => const OpenSshConnectIntent(),
  'tmux_attach' => const OpenTmuxAttachIntent(),
  'goto_tab' => SelectTabIntent(int.parse(a.param!)),
  'next_tab' => const NextTabIntent(),
  'previous_tab' => const PreviousTabIntent(),
  'new_split' => SplitPaneIntent(
    a.param == 'down' ? SplitAxis.column : SplitAxis.row,
  ),
  'goto_split' => FocusPaneIntent(_dir(a.param!)),
  'resize_split' => ResizePaneIntent(_dir(a.param!)),
  'toggle_split_zoom' => const TogglePaneZoomIntent(),
  'equalize_splits' => const EqualizePanesIntent(),
  'toggle_notifications' => const ToggleNotificationsPanelIntent(),
  'jump_to_unread' => const JumpToNextUnreadIntent(),
  'copy_to_clipboard' => const CopySelectionIntent(),
  'paste_from_clipboard' => const PasteClipboardIntent(),
  'select_all' => const SelectAllIntent(),
  'start_search' => const StartSearchIntent(),
  'navigate_search' => NavigateSearchIntent(next: a.param != 'previous'),
  'end_search' => const EndSearchIntent(),
  'edit_line' => EditLineIntent(EditLineOp.fromWire(a.param)!),
  'toggle_copy_mode' => const ToggleCopyModeIntent(),
  'increase_font_size' => FontBiggerIntent(step: double.parse(a.param ?? '1')),
  'decrease_font_size' => FontSmallerIntent(step: double.parse(a.param ?? '1')),
  'reset_font_size' => const FontResetIntent(),
  'next_region' => const NextRegionIntent(),
  'previous_region' => const PreviousRegionIntent(),
  'toggle_command_palette' => const CommandPaletteIntent(),
  'reload_config' => const ReloadConfigIntent(),
  'open_config' => const OpenConfigIntent(),
  'show_shortcuts' => const ShowShortcutsIntent(),
  'show_config_problems' => const ShowConfigProblemsIntent(),
  'run_command' => RunUserCommandIntent(a.param!),
  'text' => SendTextIntent(decodeZigString(a.param!)!),
  'csi' => SendTextIntent('\x1b[${decodeZigString(a.param!)!}'),
  'esc' => SendTextIntent('\x1b${decodeZigString(a.param!)!}'),
  'ignore' => const IgnoreKeyIntent(),
  _ => throw ArgumentError.value(a.name, 'action'),
};

/// The golden fixtures' spelling of an intent (Task 4 Step 1).
String describeIntent(Intent i) => switch (i) {
  SelectTabIntent(:final position) => 'SelectTabIntent($position)',
  SplitPaneIntent(:final axis) => 'SplitPaneIntent(${axis.name})',
  FocusPaneIntent(:final direction) => 'FocusPaneIntent(${direction.name})',
  ResizePaneIntent(:final direction) => 'ResizePaneIntent(${direction.name})',
  SelectAllIntent(:final fromMenu) =>
    fromMenu ? 'SelectAllIntent(menu)' : 'SelectAllIntent',
  EditLineIntent(:final op) => 'EditLineIntent(${op.wire})',
  NavigateSearchIntent(:final next) =>
    'NavigateSearchIntent(${next ? 'next' : 'previous'})',
  FontBiggerIntent(:final step) when step != 1 => 'FontBiggerIntent($step)',
  FontSmallerIntent(:final step) when step != 1 => 'FontSmallerIntent($step)',
  RunUserCommandIntent(:final name) => 'RunUserCommandIntent($name)',
  _ => i.runtimeType.toString(),
};

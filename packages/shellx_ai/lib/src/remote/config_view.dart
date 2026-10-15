import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_acp/shellx_acp.dart';

import '../model/session_state.dart';
import 'no_approval.dart';
import 'wire.dart';

/// V2-2b B11: the categories of settings a phone may change — the mode, the
/// model, the thinking, and the model's own (Claude's "Fast"). Every other
/// option (an agent's persona, say) stays on the computer.
const Set<String> kAiConfigCategories = {
  'mode',
  'model',
  'thought_level',
  'model_config',
};

/// The most choices of one option a phone is offered; the others stay on the
/// computer (`more`).
const int kAiConfigChoices = 40;

/// The longest name of an option or a choice, in characters.
const int kAiConfigNameChars = 60;

/// The longest id (an option's or a value) a phone is offered, in UTF-8
/// bytes: it sends it back, and an agent decides how long its ids are.
const int kAiConfigIdBytes = 256;

/// One value of a select option, as a phone may pick it.
final class AiConfigChoiceView with Redacted {
  const AiConfigChoiceView({
    required this.value,
    required this.name,
    this.group,
  });

  /// What the phone sends back (`ai.config` `value`).
  final String value;
  final String name;
  final String? group;

  Map<String, Object?> toJson() => {'v': value, 'n': name, 'g': ?group};

  /// Null without a value.
  static AiConfigChoiceView? fromJson(Map<String, Object?> j) {
    final value = jString(j, 'v');
    if (value == null) return null;
    return AiConfigChoiceView(
      value: value,
      name: jString(j, 'n') ?? value,
      group: jString(j, 'g'),
    );
  }
}

/// One setting a phone may change (V2-2b B11): a select with its [choices],
/// or a switch ([kind] `boolean`, [current] a bool).
final class AiConfigOptionView with Redacted {
  const AiConfigOptionView({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    this.current,
    this.choices = const [],
    this.more = false,
  });

  final String id;
  final String name;

  /// One of [kAiConfigCategories].
  final String category;

  /// `select` or `boolean`.
  final String kind;

  /// The value now: a choice's value (select), a bool (boolean); null when
  /// the agent said none the phone can read.
  final Object? current;
  final List<AiConfigChoiceView> choices;

  /// Choices left on the computer (too many, or too big for one message).
  final bool more;

  bool get isSwitch => kind == 'boolean';

  AiConfigOptionView withChoices(List<AiConfigChoiceView> choices) =>
      AiConfigOptionView(
        id: id,
        name: name,
        category: category,
        kind: kind,
        current: current,
        choices: choices,
        more: true,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'cat': category,
    'kind': kind,
    'cur': ?current,
    if (!isSwitch) 'choices': [for (final c in choices) c.toJson()],
    if (more) 'more': true,
  };

  /// Null without an id, a category or a kind this version reads.
  static AiConfigOptionView? fromJson(Map<String, Object?> j) {
    final id = jString(j, 'id');
    final category = jString(j, 'cat');
    final kind = jString(j, 'kind');
    if (id == null || category == null) return null;
    if (kind != 'select' && kind != 'boolean') return null;
    final current = j['cur'];
    return AiConfigOptionView(
      id: id,
      name: jString(j, 'name') ?? id,
      category: category,
      kind: kind!,
      current: kind == 'boolean'
          ? (current is bool ? current : null)
          : (current is String ? current : null),
      choices: [
        for (final c in jMaps(j, 'choices')) ?AiConfigChoiceView.fromJson(c),
      ],
      more: jBool(j, 'more'),
    );
  }
}

/// The legacy modes of an agent without config options (`session/set_mode`).
final class AiModesView with Redacted {
  const AiModesView({
    required this.current,
    this.choices = const [],
    this.more = false,
  });

  final String current;
  final List<AiConfigChoiceView> choices;
  final bool more;

  Map<String, Object?> toJson() => {
    'cur': current,
    'choices': [for (final c in choices) c.toJson()],
    if (more) 'more': true,
  };

  /// Null without a current mode.
  static AiModesView? fromJson(Map<String, Object?>? j) {
    final current = j == null ? null : jString(j, 'cur');
    if (current == null) return null;
    return AiModesView(
      current: current,
      choices: [
        for (final c in jMaps(j!, 'choices')) ?AiConfigChoiceView.fromJson(c),
      ],
      more: jBool(j, 'more'),
    );
  }
}

/// What `ai.config.get` answers (V2-2b B11): the settings of a session a
/// phone may change, without any choice that turns on a mode acting without
/// asking (R16).
final class AiConfigView with Redacted {
  const AiConfigView({this.options = const [], this.modes});

  final List<AiConfigOptionView> options;
  final AiModesView? modes;

  bool get isEmpty => options.isEmpty && modes == null;

  Map<String, Object?> toJson() => {
    'v': kAiWireVersion,
    'options': [for (final o in options) o.toJson()],
    if (modes != null) 'modes': modes!.toJson(),
  };

  static AiConfigView fromJson(Map<String, Object?> j) => AiConfigView(
    options: [
      for (final o in jMaps(j, 'options')) ?AiConfigOptionView.fromJson(o),
    ],
    modes: AiModesView.fromJson(jMap(j, 'modes')),
  );
}

String _name(String s) {
  final runes = s.runes;
  if (runes.length <= kAiConfigNameChars) return s;
  return '${String.fromCharCodes(runes.take(kAiConfigNameChars - 1))}…';
}

bool _sendable(String id) =>
    id.isNotEmpty && utf8Length(id) <= kAiConfigIdBytes;

/// V2-2b B11, R16: what a phone may change of [s]: the options of
/// [kAiConfigCategories] with the choices that turn on no mode acting
/// without asking ([aiTurnsOnNoApproval]: Claude's `bypassPermissions`, and
/// any id that merely says it); an option named like such a mode — a switch,
/// or a select too (`yolo` with `on` / `off`) — is not offered at all. Names
/// are cut to [kAiConfigNameChars] characters, choices to [kAiConfigChoices];
/// an id longer than [kAiConfigIdBytes] is not offered. The legacy modes only
/// for an agent without config options, as on the computer.
AiConfigView aiConfigViewOf(AiSessionState s) {
  final options = <AiConfigOptionView>[];
  for (final o in s.configOptions ?? const <ConfigOption>[]) {
    final category = o.category;
    if (category == null || !kAiConfigCategories.contains(category)) continue;
    if (!_sendable(o.id)) continue;
    // Named like a mode acting without asking, whatever its kind: none of
    // its values is the phone's to pick (R16).
    if (aiIsNoApprovalMode(o.id)) continue;
    switch (o.kind) {
      case ConfigKind.select:
        final all = [
          for (final c in o.choices)
            if (_sendable(c.value) &&
                !aiTurnsOnNoApproval(configId: o.id, value: c.value))
              AiConfigChoiceView(
                value: c.value,
                name: _name(c.name),
                group: c.group == null ? null : _name(c.group!),
              ),
        ];
        if (all.isEmpty) continue; // nothing a phone may pick
        final current = o.currentValue;
        options.add(
          AiConfigOptionView(
            id: o.id,
            name: _name(o.name),
            category: category,
            kind: 'select',
            current: current is String ? current : null,
            choices: all.take(kAiConfigChoices).toList(),
            more: all.length > kAiConfigChoices,
          ),
        );
      case ConfigKind.boolean:
        // Turned on it would act without asking: changed on the computer.
        if (aiTurnsOnNoApproval(configId: o.id, value: true)) continue;
        options.add(
          AiConfigOptionView(
            id: o.id,
            name: _name(o.name),
            category: category,
            kind: 'boolean',
            current: o.currentValue == true,
          ),
        );
      case ConfigKind.other:
        continue;
    }
  }
  AiModesView? modes;
  final m = s.modes;
  if (s.configOptions == null && m != null) {
    final all = [
      for (final mode in m.available)
        if (_sendable(mode.id) && !aiIsNoApprovalMode(mode.id))
          AiConfigChoiceView(value: mode.id, name: _name(mode.name)),
    ];
    if (all.isNotEmpty) {
      modes = AiModesView(
        current: m.currentModeId,
        choices: all.take(kAiConfigChoices).toList(),
        more: all.length > kAiConfigChoices,
      );
    }
  }
  return AiConfigView(options: options, modes: modes);
}

/// [view] as a body within [kAiRecordBytes] (one that is bigger would drop
/// the phone's whole channel): while it is too big, the list with the most
/// choices loses a quarter of them (one at least) and says there are more;
/// with no choice left anywhere, the last option goes, then the modes.
Uint8List encodeConfigView(AiConfigView view) {
  final options = [...view.options];
  var modes = view.modes;
  while (true) {
    final json = jsonEncode(
      AiConfigView(options: options, modes: modes).toJson(),
    );
    if (utf8Length(json) <= kAiRecordBytes) {
      return Uint8List.fromList(utf8.encode(json));
    }
    var most = -1;
    var count = 0;
    for (var i = 0; i < options.length; i++) {
      if (options[i].choices.length > count) {
        most = i;
        count = options[i].choices.length;
      }
    }
    final m = modes;
    if (m != null && m.choices.length > count) {
      most = options.length;
      count = m.choices.length;
    }
    if (count > 0) {
      final keep = count - (count < 4 ? 1 : count ~/ 4);
      if (most == options.length) {
        modes = AiModesView(
          current: m!.current,
          choices: m.choices.take(keep).toList(),
          more: true,
        );
      } else {
        options[most] = options[most].withChoices(
          options[most].choices.take(keep).toList(),
        );
      }
    } else if (options.isNotEmpty) {
      options.removeLast();
    } else {
      modes = null; // a view of nothing fits
    }
  }
}

/// V2-2b B11, R16: whether a phone may set option [id] of [s] to [value] now:
/// null when it may; `on_computer` for a value that turns on a mode acting
/// without asking, or for an option named like one (a switch or a select,
/// whatever the value) — whatever the phone was offered, and whatever the
/// agent offers now; `refused` for an option or a value the phone is not
/// offered now.
String? aiConfigRefusal(AiSessionState s, String id, Object? value) {
  if (value is! String && value is! bool) return 'refused';
  if (aiTurnsOnNoApproval(configId: id, value: value)) return 'on_computer';
  if (aiIsNoApprovalMode(id)) return 'on_computer'; // named like one
  final option = (s.configOptions ?? const <ConfigOption>[])
      .where((o) => o.id == id)
      .firstOrNull;
  if (option == null) return 'refused';
  final category = option.category;
  if (category == null || !kAiConfigCategories.contains(category)) {
    return 'refused';
  }
  switch (option.kind) {
    case ConfigKind.select:
      if (value is! String || !option.choices.any((c) => c.value == value)) {
        return 'refused';
      }
    case ConfigKind.boolean:
      if (aiTurnsOnNoApproval(configId: id, value: true)) return 'on_computer';
      if (value is! bool) return 'refused';
    case ConfigKind.other:
      return 'refused';
  }
  return null;
}

/// V2-2b B11, R16: whether a phone may set the legacy mode [modeId] of [s]
/// now: null when it may; `on_computer` for a mode acting without asking;
/// `refused` for a mode not offered (none of the agent's, or an agent with
/// config options, whose mode is an option).
String? aiModeRefusal(AiSessionState s, String modeId) {
  if (aiIsNoApprovalMode(modeId)) return 'on_computer';
  final modes = s.modes;
  if (s.configOptions != null || modes == null) return 'refused';
  if (!modes.available.any((m) => m.id == modeId)) return 'refused';
  return null;
}

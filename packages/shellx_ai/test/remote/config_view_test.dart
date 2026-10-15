import 'dart:convert';

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

/// Claude's own `configOptions` (adapter 0.90.0, trimmed), and its persona
/// option, which has no category.
const _claude = <Map<String, Object?>>[
  {
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Manual'},
      {'value': 'acceptEdits', 'name': 'Accept edits'},
      {'value': 'plan', 'name': 'Plan'},
      {'value': 'auto', 'name': 'Auto'},
      {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
    ],
  },
  {
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': 'opus',
    'options': [
      {'value': 'opus', 'name': 'Opus 5.5'},
      {'value': 'sonnet', 'name': 'Sonnet 5.5'},
    ],
  },
  {
    'id': 'effort',
    'name': 'Effort',
    'category': 'thought_level',
    'type': 'select',
    'currentValue': 'high',
    'options': [
      {'value': 'low', 'name': 'Low'},
      {'value': 'high', 'name': 'High'},
    ],
  },
  {
    'id': 'fast',
    'name': 'Fast',
    'category': 'model_config',
    'type': 'boolean',
    'currentValue': false,
  },
  {
    'id': 'agent',
    'name': 'Agent',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Default'},
    ],
  },
];

AiSessionState _state([List<Map<String, Object?>> options = _claude]) =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p')
      ..configOptions = [for (final j in options) ?ConfigOption.fromJson(j)];

AiConfigView _roundTrip(AiConfigView view) =>
    AiConfigView.fromJson(decodeBody(encodeConfigView(view))!);

/// V2-2b B11, R16: what a phone may see and set of a session's settings.
void main() {
  test('mode, model, thinking and the model\'s own; never a choice acting '
      'without asking; the persona stays on the computer', () {
    final view = _roundTrip(aiConfigViewOf(_state()));
    expect(view.options.map((o) => (o.id, o.category, o.kind)), [
      ('mode', 'mode', 'select'),
      ('model', 'model', 'select'),
      ('effort', 'thought_level', 'select'),
      ('fast', 'model_config', 'boolean'),
    ]);
    final mode = view.options.first;
    expect(mode.current, 'default');
    expect(mode.choices.map((c) => c.value), [
      'default',
      'acceptEdits',
      'plan',
      'auto',
    ]);
    expect(view.options[1].choices.map((c) => c.name), [
      'Opus 5.5',
      'Sonnet 5.5',
    ]);
    expect(view.options.last.current, isFalse);
    expect(view.modes, isNull);
  });

  test('R16: an id that only says it (yolo, clearAndBypass, '
      'danger-full-access) is never offered, nor a switch named like one', () {
    final view = aiConfigViewOf(
      _state([
        {
          'id': 'mode',
          'name': 'Mode',
          'category': 'mode',
          'type': 'select',
          'currentValue': 'default',
          'options': [
            {'value': 'default', 'name': 'Ask'},
            {'value': 'YOLO-mode', 'name': 'Yolo'},
            {'value': 'clearAndBypass', 'name': 'Clear'},
            {'value': 'sandbox:danger-full-access', 'name': 'Full'},
          ],
        },
        {
          'id': 'yolo',
          'name': 'Yolo',
          'category': 'model_config',
          'type': 'boolean',
          'currentValue': false,
        },
      ]),
    );
    expect(view.options.single.choices.map((c) => c.value), ['default']);
  });

  test('names cut to 60 characters, 40 choices at most (more), and an id too '
      'long to send is not offered', () {
    final view = aiConfigViewOf(
      _state([
        {
          'id': 'model',
          'name': 'M' * 100,
          'category': 'model',
          'type': 'select',
          'currentValue': 'm0',
          'options': [
            {'value': 'x' * 300, 'name': 'Too long'},
            for (var i = 0; i < 50; i++) {'value': 'm$i', 'name': 'ố' * 80},
          ],
        },
      ]),
    );
    final model = view.options.single;
    expect(model.name.runes.length, 60);
    expect(model.name, endsWith('…'));
    expect(model.choices, hasLength(40));
    expect(model.choices.first.value, 'm0');
    expect(model.choices.first.name.runes.length, 60);
    expect(model.more, isTrue);
  });

  test('legacy modes only for an agent without config options; a no-approval '
      'mode left out', () {
    final s = AiSessionState(agentId: 'gemini', agentName: 'Gemini', cwd: '/p')
      ..modes = SessionModes.fromJson({
        'currentModeId': 'default',
        'availableModes': [
          {'id': 'default', 'name': 'Default'},
          {'id': 'autoEdit', 'name': 'Auto edit'},
          {'id': 'yolo', 'name': 'YOLO'},
        ],
      });
    final view = _roundTrip(aiConfigViewOf(s));
    expect(view.options, isEmpty);
    expect(view.modes!.current, 'default');
    expect(view.modes!.choices.map((c) => c.value), ['default', 'autoEdit']);
    expect(aiConfigViewOf(_state()..modes = s.modes).modes, isNull);
  });

  test('Review Focus 3: many options with long names and ids still fit one '
      'body; what was cut says more', () {
    final s = _state([
      for (var o = 0; o < 12; o++)
        {
          'id': 'o$o${'i' * 200}',
          'name': 'ữ' * 70,
          'category': 'model',
          'type': 'select',
          'currentValue': 'v0',
          'options': [
            for (var i = 0; i < 40; i++)
              {'value': 'v$i${'w' * 240}', 'name': 'ữ' * 70},
          ],
        },
    ]);
    final body = encodeConfigView(aiConfigViewOf(s));
    expect(body.length, lessThanOrEqualTo(kAiRecordBytes));
    final view = AiConfigView.fromJson(decodeBody(body)!);
    expect(view.options, isNotEmpty);
    expect(view.options.any((o) => o.more), isTrue);
  });

  group('Review Focus 5: what a phone may set', () {
    test('an offered choice or switch: null', () {
      final s = _state();
      expect(aiConfigRefusal(s, 'model', 'sonnet'), isNull);
      expect(aiConfigRefusal(s, 'mode', 'plan'), isNull);
      expect(aiConfigRefusal(s, 'fast', true), isNull);
    });

    test('a value acting without asking is kept for the computer, offered or '
        'not, whatever the option', () {
      final s = _state([
        ..._claude,
        {
          'id': 'yolo',
          'name': 'Yolo',
          'category': 'model_config',
          'type': 'boolean',
          'currentValue': false,
        },
      ]);
      for (final (id, value) in <(String, Object)>[
        ('mode', 'bypassPermissions'),
        ('mode', 'yolo'),
        ('mode', 'clearAndBypass'),
        ('model', 'danger-full-access'),
        ('yolo', true),
        ('yolo', false),
        ('unknown', 'bypass'),
      ]) {
        expect(
          aiConfigRefusal(s, id, value),
          'on_computer',
          reason: '$id=$value',
        );
      }
    });

    test('an option or value not offered now is refused', () {
      final s = _state();
      expect(aiConfigRefusal(s, 'agent', 'default'), 'refused');
      expect(aiConfigRefusal(s, 'model', 'gpt'), 'refused');
      expect(aiConfigRefusal(s, 'nothing', 'x'), 'refused');
      expect(aiConfigRefusal(s, 'fast', 'yes'), 'refused');
      expect(aiConfigRefusal(s, 'model', 3), 'refused');
      expect(aiConfigRefusal(s, 'model', null), 'refused');
    });

    test('legacy modes: one of the agent\'s; a no-approval one is for the '
        'computer; none for an agent with config options', () {
      final s = AiSessionState(agentId: 'g', agentName: 'G', cwd: '/p')
        ..modes = SessionModes.fromJson({
          'currentModeId': 'default',
          'availableModes': [
            {'id': 'default', 'name': 'Default'},
            {'id': 'plan', 'name': 'Plan'},
          ],
        });
      expect(aiModeRefusal(s, 'plan'), isNull);
      expect(aiModeRefusal(s, 'other'), 'refused');
      expect(aiModeRefusal(s, 'yolo'), 'on_computer');
      expect(aiModeRefusal(s, 'bypassPermissions'), 'on_computer');
      expect(aiModeRefusal(_state()..modes = s.modes, 'plan'), 'refused');
    });
  });

  test('a body of another shape reads as what it says, never throws', () {
    final view = AiConfigView.fromJson(
      jsonDecode(
            '{"options":[{"id":"m","cat":"model","kind":"select","cur":3,'
            '"choices":[{"v":"a"},{"n":"no value"},7]},'
            '{"id":"x","cat":"mode","kind":"slider"},{"cat":"mode"}],'
            '"modes":{"choices":[]}}',
          )
          as Map<String, Object?>,
    );
    expect(view.options.single.id, 'm');
    expect(view.options.single.current, isNull);
    expect(view.options.single.choices.single.name, 'a');
    expect(view.modes, isNull);
  });

  test('toString never shows a name or a value', () {
    final view = aiConfigViewOf(_state());
    for (final o in [view, ...view.options, ...view.options.first.choices]) {
      expect(o.toString(), '…');
    }
  });
}

import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/ai_rig.dart';

const _phone = 'b0000000-0000-4000-8000-000000000002';
const _sid = 'ep.-1';

/// Claude's options (trimmed), with a switch named like a mode acting
/// without asking.
const _options = <Map<String, Object?>>[
  {
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Manual'},
      {'value': 'plan', 'name': 'Plan'},
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
    'id': 'yolo',
    'name': 'Yolo',
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

(HubRig, AiSessionState) _rig() {
  final rig = HubRig();
  final s = rig.source.add(-1)
    ..configOptions = [for (final j in _options) ?ConfigOption.fromJson(j)];
  return (rig, s);
}

AiConfigSet _set(int rid, Map<String, Object?> body) =>
    AiConfigSet(sid: _sid, rid: rid, body: encodeBody(body));

/// V2-2b B11: mode and model from the phone.
void main() {
  test('the choices a phone may make come as a body; none acting without '
      'asking; the listing names the feature', () async {
    final (rig, _) = _rig();
    rig.hub.handle(_phone, const AiConfigGet(sid: _sid, rid: 1));
    await pumpEventQueue();
    final result = rig.last<AiResult>(_phone);
    expect((result.rid, result.ok), (1, true));
    final view = AiConfigView.fromJson(decodeBody(result.body)!);
    expect(view.options.map((o) => o.id), ['mode', 'model']);
    expect(view.options.first.choices.map((c) => c.value), ['default', 'plan']);
    rig.hub.handle(_phone, const AiList());
    final listing = AiListing.fromJson(
      decodeBody(rig.last<AiListResult>(_phone).body)!,
      available: true,
    );
    expect(listing.features, contains(AiFeature.config));
  });

  test('an offered choice is set; the agent saying no is refused', () async {
    final (rig, s) = _rig();
    final control = rig.source.controls[-1]!;
    rig.hub.handle(_phone, _set(2, {'id': 'model', 'value': 'sonnet'}));
    await pumpEventQueue();
    expect(rig.last<AiResult>(_phone).ok, isTrue);
    expect(control.configs, [('model', 'sonnet')]);
    expect(
      s.configOptions!.firstWhere((o) => o.id == 'model').currentValue,
      'sonnet',
    );
    control.failConfig = StateError('the agent said no');
    rig.hub.handle(_phone, _set(3, {'id': 'model', 'value': 'opus'}));
    await pumpEventQueue();
    expect(rig.last<AiResult>(_phone).code, 'refused');
  });

  test('Review Focus 5: a value acting without asking is the computer\'s, '
      'whatever the phone sends; nothing reaches the runtime', () async {
    final (rig, _) = _rig();
    final control = rig.source.controls[-1]!;
    final bodies = <Map<String, Object?>>[
      {'id': 'mode', 'value': 'bypassPermissions'},
      {'id': 'mode', 'value': 'yolo'},
      {'id': 'mode', 'value': 'clearAndBypass'},
      {'id': 'yolo', 'value': true},
      {'mode': 'bypassPermissions'},
    ];
    for (final (i, body) in bodies.indexed) {
      rig.hub.handle(_phone, _set(10 + i, body));
    }
    await pumpEventQueue();
    final codes = {
      for (final r in rig.to(_phone).whereType<AiResult>()) r.rid: r.code,
    };
    expect(codes, {
      10: 'on_computer',
      11: 'on_computer',
      12: 'on_computer',
      13: 'on_computer',
      14: 'on_computer',
    });
    expect(control.configs, isEmpty);
    expect(control.modes, isEmpty);
  });

  test('refused: an option not offered, a value not among its choices, a '
      'switch given a word, a body that is no JSON object', () async {
    final (rig, _) = _rig();
    final control = rig.source.controls[-1]!;
    rig.hub
      ..handle(_phone, _set(20, {'id': 'agent', 'value': 'default'}))
      ..handle(_phone, _set(21, {'id': 'model', 'value': 'gpt'}))
      ..handle(_phone, _set(22, {'value': 'opus'}))
      ..handle(_phone, _set(23, {'mode': 'plan'})) // it has options: no modes
      ..handle(
        _phone,
        AiConfigSet(sid: _sid, rid: 24, body: encodeBody(const {})),
      );
    await pumpEventQueue();
    final codes = {
      for (final r in rig.to(_phone).whereType<AiResult>()) r.rid: r.code,
    };
    expect(codes, {
      20: 'refused',
      21: 'refused',
      22: 'refused',
      23: 'refused',
      24: 'refused',
    });
    expect(control.configs, isEmpty);
  });

  test('a legacy mode is set as a mode', () async {
    final rig = HubRig();
    rig.source.add(-1).modes = SessionModes.fromJson({
      'currentModeId': 'default',
      'availableModes': [
        {'id': 'default', 'name': 'Default'},
        {'id': 'plan', 'name': 'Plan'},
      ],
    });
    rig.hub.handle(_phone, _set(30, {'mode': 'plan'}));
    await pumpEventQueue();
    expect(rig.last<AiResult>(_phone).ok, isTrue);
    expect(rig.source.controls[-1]!.modes, ['plan']);
  });

  test('a session that is not there is not_found; the answer goes only to '
      'the phone that asked, not to one back on a new channel', () async {
    final (rig, _) = _rig();
    rig.hub.handle(_phone, const AiConfigGet(sid: 'ep.-9', rid: 40));
    await pumpEventQueue();
    expect(rig.last<AiResult>(_phone).code, 'not_found');
    rig.hub.handle(_phone, _set(41, {'id': 'model', 'value': 'sonnet'}));
    rig.hub
      ..phoneGone(_phone)
      ..handle(_phone, const AiList()); // the same phone, a new channel
    await pumpEventQueue();
    expect(rig.to(_phone).whereType<AiResult>().map((r) => r.rid), [40]);
  });
}

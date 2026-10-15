import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:test/test.dart';

final _at = DateTime.utc(2026, 10, 15, 9);

PermissionRequest _perm(String toolCallId) => PermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': {'toolCallId': toolCallId, 'title': 'Edit a.ts'},
  'options': [
    {'optionId': 'allow', 'name': 'Yes', 'kind': 'allow_once'},
    {'optionId': 'reject', 'name': 'No', 'kind': 'reject_once'},
  ],
});

ElicitationRequest _ask() => ElicitationRequest.fromJson({
  'mode': 'form',
  'message': 'Which?',
  'requestedSchema': {
    'type': 'object',
    'properties': {
      'pick': {'type': 'string'},
    },
  },
});

AiSessionState _state() =>
    AiSessionState(agentId: 'claude', agentName: 'Claude', cwd: '/p');

/// V2-2b B3 (R1): permission, question and queue ids come from one counter
/// for the whole run, shared by every state — a pane whose runtime is
/// replaced gets a new state, and its first request must not be named like
/// the old runtime's.
void main() {
  test('the requests of two states never share an id', () {
    final a = _state();
    final b = _state();
    final ids = [
      a.addPermission(_perm('c1'), _at).id,
      b.addPermission(_perm('c1'), _at).id,
      a.addAsk(_ask())!.id,
      b.addAsk(_ask())!.id,
      a.enqueue(const [TextBlock('one')])!.id,
      b.enqueue(const [TextBlock('two')])!.id,
    ];
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('a state made later never starts again from an id an earlier one '
      'used', () {
    final first = _state().addPermission(_perm('c1'), _at).id;
    final next = _state().addPermission(_perm('c1'), _at).id;
    expect(next, greaterThan(first));
  });
}

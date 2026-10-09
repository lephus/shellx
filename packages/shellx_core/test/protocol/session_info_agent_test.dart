import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _entry([Map<String, Object?> extra = const {}]) => {
  'id': 1,
  'index': 1,
  'shell': 'zsh',
  'created_at': 1,
  'attached': false,
  'kind': 'desktop',
  'app': 'Term',
  'title': 't',
  ...extra,
};

SessionInfo _decode(Map<String, Object?> e) =>
    (AppMessage.fromMap({
              't': 'session.list.result',
              'sessions': [e],
            })
            as SessionListResult?)!
        .sessions
        .single;

void main() {
  test('without the keys the map is byte-identical to before A12', () {
    const info = SessionInfo(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: 1,
      attached: false,
    );
    expect(info.toMap().containsKey('agent'), isFalse);
    expect(info.toMap().containsKey('agentState'), isFalse);
  });

  test('round trip with the keys; written only when non-empty', () {
    const info = SessionInfo(
      id: 1,
      index: 1,
      shell: 'zsh',
      createdAt: 1,
      attached: false,
      kind: SessionKind.desktop,
      agent: 'claude',
      agentState: 'needs_input',
    );
    expect(info.toMap()['agent'], 'claude');
    expect(info.toMap()['agentState'], 'needs_input');
    final back = _decode(info.toMap());
    expect((back.agent, back.agentState), ('claude', 'needs_input'));
  });

  test('anything outside the closed set decodes to empty', () {
    for (final e in [
      {'agent': 'claude', 'agentState': 'bogus'},
      {'agent': 'rm -rf', 'agentState': 'running'},
      {'agent': 'claude'},
      {'agentState': 'running'},
    ]) {
      final s = _decode(_entry(e));
      expect((s.agent, s.agentState), ('', ''), reason: '$e');
    }
  });

  test('a legacy entry (no keys) decodes with empty agent', () {
    final s = _decode(_entry());
    expect((s.agent, s.agentState), ('', ''));
  });
}

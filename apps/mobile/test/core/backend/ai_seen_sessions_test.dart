import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/remote.dart';
import 'package:shellx_mobile/core/backend/ai_seen_sessions.dart';

AiSessionInfo _info(String sid, {String acp = 'sess-1'}) => AiSessionInfo(
  sid: sid,
  agentId: 'claude',
  agentName: 'Claude',
  title: '',
  state: AiRemoteState.idle,
  cwd: '/p',
  acpSessionId: acp,
);

/// V2-2b B22, B23: what the phone remembers of the sessions listings named.
void main() {
  test('every session of every listing, the latest entry of each', () {
    final seen = AiSeenSessions()
      ..note(
        AiListing(
          sessions: [
            _info('e.-1'),
            _info('e.-2', acp: 'sess-2'),
          ],
        ),
      )
      ..note(AiListing(sessions: [_info('e.-1', acp: 'sess-9')]));
    expect(seen.of('e.-1')!.acpSessionId, 'sess-9');
    expect(seen.of('e.-2')!.acpSessionId, 'sess-2', reason: 'a session a later listing left out is still known');
    expect(seen.of('e.-3'), isNull);
  });

  test('bounded: the oldest go first', () {
    final seen = AiSeenSessions();
    for (var i = 0; i < AiSeenSessions.capacity + 10; i++) {
      seen.note(AiListing(sessions: [_info('e.$i')]));
    }
    expect(seen.length, AiSeenSessions.capacity);
    expect(seen.of('e.0'), isNull);
    expect(seen.of('e.${AiSeenSessions.capacity + 9}'), isNotNull);
  });
}
